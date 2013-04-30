package MC;

use v5.12;
use warnings;
use Carp;
use Mojo::IOLoop;

use constant MEMCACHED_PORT => 11211;
use constant DEBUG => $ENV{MC_DEBUG} // 0;

sub new {
  my $type = shift;
  my $self = {};
  @{$self}{qw/address port/} = @_;
  $self->{address} //= 'localhost';
  $self->{port} //= MEMCACHED_PORT;
  $self->{ioloop} = Mojo::IOLoop->new;
  bless $self, $type;
  return $self;
}

sub set {
  my $self = shift;
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
  my ($key, $flags, $value, $opt) = @_;
  $opt->{exptime} //= 0;
  $opt->{noreply} //= '';

  my $data = join ' ', 'set', $key, $flags, $opt->{exptime}, length $value;
  $data .= ' noreply' if $opt->{noreply};
  $data .= "\r\n${value}\r\n";

  my $req = {data => $data, name => 'set'};
  $self->_request($req, $cb);
}

sub get {
  my $self   = shift;
  my $cb     = ref $_[-1] eq 'CODE' ? pop : undef;
  my ($keys) = @_;
  $keys = [$keys] unless ref $keys eq 'ARRAY';
  my $k = join ' ', @$keys;

  my $data = "get ${k}\r\n";
  my $req = {data => $data, name => 'get'};
  $self->_request($req, $cb);
}

sub delete {
  my $self = shift;
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
  my ($key, $opt) = @_;
  $opt->{noreply} //= '';

  my $data = "delete ${key}\r\n";
  $data .= ' noreply' if $opt->{noreply};
  my $req = {data => $data, name => 'delete'};
  $self->_request($req, $cb);
}

sub _request {
  my ($self, $req, $cb) = @_;
  if ($cb) {
    $self->_clean unless $self->{async};
    $self->{async} = 1;
    $req->{cb}     = $cb;
    push @{$self->{queue}}, $req;
    $self->{connection} ? $self->_write : $self->_connect;
    return;
  }

  $self->_clean if $self->{async};
  $self->{async} = 0;
  my ($err, $response);
  $req->{cb} = sub {
    my $self = shift;
    ($err, $response) = @_;
    $self->{ioloop}->stop;
  };
  push @{$self->{queue}}, $req;

  $self->{connection} ? $self->_write : $self->_connect;
  $self->{ioloop}->start;

  croak $err if $err;
  return $response;
}

sub DESTROY {
  shift->_clean;
}

sub _clean {
  my $self = shift;
  my $loop = $self->{async} ? Mojo::IOLoop->singleton : $self->{ioloop};
  return unless $loop;
  if (my $connection = delete $self->{connection}) {
    $loop->remove($connection);
  }
  delete $self->{queue};
}

sub _connect {
  my $self = shift;
  my $loop = $self->{async} ? Mojo::IOLoop->singleton : $self->{ioloop};
  $self->{connection} = $loop->client(
    {address => $self->{address}, port => $self->{port}} => sub {
      my ($loop, $err, $stream) = @_;
      if ($err) {
        warn "Error while connect: $err" if DEBUG;
        return $self->_response($err);
      }
      warn "Connected to $self->{address}" if DEBUG;
      $stream->on(
        read => sub {
          my ($stream, $bytes) = @_;
          $self->_read($bytes);
        });
      $stream->on(
        error => sub {
          my ($client, $err) = @_;
          warn "Error in connection: $err" if DEBUG;
          return $self->_response($err);
        });
      $stream->on(
        close => sub {
          if (my $connection = delete $self->{connection}) {
            $loop->remove($connection);
          }
          warn 'Close connection' if DEBUG;
        });
      $self->_write;
    });
}

sub _response {
  my ($self, $err, $res) = @_;
  my $req = shift @{$self->{queue}};
  my $cb  = $req->{cb};
  $self->$cb($err, $res);
}

sub _read {
  my ($self, $bytes, $cb) = @_;
  warn "Read response chunk: '$bytes'" if DEBUG;
  $self->{buffer} .= $bytes;
  if ($self->{buffer} =~ /\r\n$/) {
    my ($err, $response) = $self->_parse($self->{queue}->[0]->{name}, \$self->{buffer});
    $self->_response($err, $response);
  }
}

sub _parse {
  my ($self, $type, $buffer) = @_;
  my ($err, $response);
  $$buffer =~ s/^(ERROR\r\n)+//;
  given ($type) {
    when ('set') {
      $$buffer =~ m/
        ^
        (?'RESPONSE'
            ERROR                        # General error
          | CLIENT_ERROR\s[\w\s]+        # Input error
          | SERVER_ERROR\s[\w\s]+        # Server error
          | STORED                       # Set OK
          | NOT_STORED                   # Add or Replace fail
          | EXISTS
          | NOT_FOUND
        )
        \r\n
      /xm;
      $$buffer = $';
      if ($+{RESPONSE} eq 'STORED') {
        $response = 1;
      } else {
        $response = undef;
        $err      = "Protocol error: $+{RESPONSE}";
      }
    }
    when ('delete') {
      $$buffer =~ m/
        ^
        (?'RESPONSE' DELETED | NOT_FOUND)
        \r\n
      /xm;
      $$buffer  = $';
      $response = undef if $+{RESPONSE} eq 'NOT_FOUND';
      $response = 1 if $+{RESPONSE} eq 'DELETED';
    }
    when ('get') {
      while (
        $$buffer =~ m/
            ^VALUE
            \s(?'KEY'\w+)
            \s(?'FLAGS'\d+)
            \s(?'BYTES'\d+)
            (?:\s\d+)?           # CAS
            \r\n
          /xm
        ) {
        $$buffer = $';
        my $key   = $+{KEY};
        my $flags = $+{FLAGS};
        my $data  = substr $$buffer, 0, $+{BYTES}, '';
        $$buffer =~ s/^\r\n//;
        $response->{$key} = {value => $data, flags => $flags};
        last if $$buffer =~ m/^END\r\n/;
      }
      $$buffer =~ s/^END\r\n//;
      my @keys = keys %$response;
      if (1 == @keys) {
        $response =
          {value => $response->{$keys[0]}->{value}, flags => $response->{$keys[0]}->{flags}};
      } elsif (0 == @keys) {
        $response = undef;
      }
    }
  }
  return ($err, $response);
}

sub _write {
  my $self   = shift;
  my $loop   = $self->{async} ? Mojo::IOLoop->singleton : $self->{ioloop};
  my $stream = $loop->stream($self->{connection});
  return unless $stream;
  my $req = $self->{queue}->[0];
  warn "Write request chunk: '$req->{data}'" if DEBUG;
  $stream->write($req->{data});
}

1;
