use Test::More;
use MC;
use Mojo::IOLoop;

my $mc = MC->new('localhost', 11211);

isa_ok $mc, 'MC';
can_ok $mc, qw/set get delete/;

is $mc->{address}, 'localhost', 'address is valid';
is $mc->{port},    11211,       'port is valid';

## Blocking API
## Set
my $value = 'qwerasdf';
my $bin = join '', map chr, 0 .. 255;
$mc->set('q1', 13, $value, {});
$mc->set('q2',  7, $value x 2, {exptime => 100});
$mc->set('end', 0, 'END',      {exptime => 100});
$mc->set('bin', 0, $bin);
eval { $mc->set('bin' x 90, 0, $bin); };
like $@, qr/Protocol error/, 'general error';
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
## Delete
$res = $mc->delete('end');
is $res, 1, 'delete ok';
$res = $mc->delete('bin');
is $res, 1, 'delete ok';
$res = $mc->delete('not_exists');
ok !$res, 'delete ok';
$res = $mc->get('end');
ok !$res, 'get ok';
$res = $mc->get([qw/end bin/]);
ok !$res, 'get ok';

done_testing();
