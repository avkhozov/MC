use Test::More;
use MC;
use Mojo::IOLoop;

my $mc    = MC->new('localhost', 11211);
my $value = 'qwerasdf';
my $bin   = join '', map chr, 0 .. 255;

my $delay = Mojo::IOLoop->delay(
  sub {
    my $delay = shift;
    $mc->set(('a1', 23, $value, {}) => $delay->begin);
  },
  sub {
    my ($delay, $err, $res) = @_;
    ok !$err, 'empty error';
    $mc->set(('a2', 54, $value x 3) => $delay->begin);
  },
  sub {
    my ($delay, $err, $res) = @_;
    ok !$err, 'empty error';
    $mc->get(a2 => $delay->begin);
  },
  sub {
    my ($delay, $err, $res) = @_;
    ok !$err, 'empty error';
    is $res->{value}, $value x 3, 'retrieve value is valid';
    is $res->{flags}, 54, 'retrieve flags is valid';
    $mc->get([qw/a2 a1/] => $delay->begin);
  },
  sub {
    my ($delay, $err, $res) = @_;
    ok !$err, 'empty error';
    is $res->{a1}{value}, $value, 'multi retrieve value is valid';
    is $res->{a1}{flags}, 23, 'multi retrieve flags is valid';
    is $res->{a2}{value}, $value x 3, 'multi retrieve value is valid';
    is $res->{a2}{flags}, 54, 'multi retrieve flags is valid';
    $mc->set(('big' x 100, 54, $value) => $delay->begin);
  },
  sub {
    my ($delay, $err, $res) = @_;
    like $err, qr/Protocol error/, 'general error';
    ok !$res, 'empty response';
    $mc->delete(a2 => $delay->begin);
  },
  sub {
    my ($delay, $err, $res) = @_;
    ok !$err, 'empty error';
    is $res, 1, 'response is valid';
  });
$delay->wait;

done_testing();
