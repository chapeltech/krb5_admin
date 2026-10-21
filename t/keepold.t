use strict;
use warnings;

use Test::More;

use Krb5Admin::C;
use Krb5Admin::CLI;
use Krb5Admin::Local;

$ENV{KRB5_CONFIG} = './t/krb5.conf';

my $kmdb = Krb5Admin::Local->new({config => './t/krb5_admind.conf'});
my $ctx = Krb5Admin::C::krb5_init_context();
my $hndl = Krb5Admin::C::krb5_get_kadm5_hndl($ctx, undef, undef);
my $princ = 'krbtgt/KEEPOLD.TEST@TEST.REALM';
my $output = '';
open(my $out, '>', \$output) or die $!;
my $cli = Krb5Admin::CLI->new(out => $out, err => $out);
$cli->set_obj($kmdb);

eval { $kmdb->remove($princ); };
$kmdb->create($princ);

sub get_keys {
	return [sort { $a->{enctype} <=> $b->{enctype} ||
	    $a->{kvno} <=> $b->{kvno} }
	    map { {enctype => $_->{enctype}, kvno => $_->{kvno},
	    key => $_->{key}} }
	    @{Krb5Admin::C::krb5_getkey($ctx, $hndl, $princ)}];
}

for my $test (
	['password with +keepold', 1, sub {
		$cli->run_cmd('change_passwd', $princ, 'New-password-1!',
		    '+keepold');
	}],
	['password with +needchange and +keepold', 1, sub {
		$cli->run_cmd('change_passwd', $princ, 'New-password-2!',
		    '+keepold', '+needchange');
	}],
	['password without +keepold', 0, sub {
		$cli->run_cmd('change_passwd', $princ, 'New-password-3!');
	}],
	['reset with +keepold', 1, sub {
		$cli->run_cmd('reset_passwd', $princ, '+keepold');
	}],
	['reset without +keepold', 0, sub {
		$cli->run_cmd('reset_passwd', $princ);
	}],
	['negotiated password with keepold', 1, sub {
		my ($secret, $public) =
		    @{Krb5Admin::C::curve25519_pass1($ctx)};
		$kmdb->generate_ecdh_key1('change', $princ);
		$kmdb->change($princ, -1, public => $public,
		    enctypes => [18], keepold => 1);
		0;
	}],
	['negotiated password without keepold', 0, sub {
		my ($secret, $public) =
		    @{Krb5Admin::C::curve25519_pass1($ctx)};
		$kmdb->generate_ecdh_key1('change', $princ);
		$kmdb->change($princ, -1, public => $public, enctypes => [18]);
		0;
	}],
	['random password with keepold', 1, sub {
		Krb5Admin::C::krb5_randpass($ctx, $hndl, $princ, [18], 1);
		0;
	}],
	['random password without keepold', 0, sub {
		Krb5Admin::C::krb5_randpass($ctx, $hndl, $princ, [18]);
		0;
	}],
	['random keys with keepold', 1, sub {
		Krb5Admin::C::krb5_randkey($ctx, $hndl, $princ, 1);
		0;
	}],
	['random keys without keepold', 0, sub {
		Krb5Admin::C::krb5_randkey($ctx, $hndl, $princ);
		0;
	}]) {
	subtest $test->[0] => sub {
		my $old = get_keys();
		my $kvno = $kmdb->query($princ)->{kvno};
		is($test->[2]->(), 0, 'key change succeeded') or diag($output);
		is($kmdb->query($princ)->{kvno}, $kvno + 1, 'KVNO advanced');
		my @old = grep { $_->{kvno} <= $kvno } @{get_keys()};
		is_deeply(\@old, $test->[1] ? $old : [],
		    'old key material follows keepold option');
		if ($test->[0] =~ /reset|needchange/) {
			ok(grep({ $_ eq '+needchange' }
			    @{$kmdb->query($princ)->{attributes}}),
			    'password change required');
		}
	};
}

my $kvno = $kmdb->query($princ)->{kvno};
eval { $kmdb->change_passwd($princ, 'No-change!', '+keepol'); };
ok($@, 'unknown option rejected');
is($kmdb->query($princ)->{kvno}, $kvno, 'invalid option did not change keys');

$kmdb->remove($princ);
done_testing();
