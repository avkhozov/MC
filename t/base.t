use Test::More;
use MC;
use Mojo::IOLoop;

my $mc = MC->new('localhost', 11211);

isa_ok $mc, 'MC';
can_ok $mc, qw/set/;

is $mc->{address}, 'localhost', 'address is valid';
is $mc->{port},    11211,       'port is valid';

## Blocking API
## Set
my $value = 'qwerasdf';
my $bin = join '', map chr, 0..255;
$mc->set('q1', 13, $value, {});
$mc->set('q2', 7, $value x 2, {exptime => 100});
$mc->set('end', 0, 'END', {exptime => 100});
$mc->set('bin', 0, $bin);
## Get
my $res = $mc->get('q1');
is $res->{value}, $value, 'retrieve value is valid';
is $res->{flags}, 13, 'retrieve flags is valid';
$res = $mc->get(['q1', 'q2']);
is $res->{q1}{value}, $value, 'multi retrieve value is valid';
is $res->{q1}{flags}, 13, 'multi retrieve flags is valid';
is $res->{q2}{value}, $value x 2, 'multi retrieve value is valid';
is $res->{q2}{flags}, 7, 'multi retrieve flags is valid';
$res = $mc->get('end');
is $res->{value}, 'END', 'retrieve value is valid';
$res = $mc->get('random_key');
ok !$res->{value}, 'retrieve value is valid';
$res = $mc->get('bin');
is $res->{value}, $bin, 'retrieve value is valid';

## Async API
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
        $mc->get('a2' => $delay->begin);
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
    }
);
$delay->wait;

done_testing();
