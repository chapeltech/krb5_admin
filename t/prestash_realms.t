#!/usr/pkg/bin/perl

use File::Temp qw/tempfile/;
use Test::More;

use Krb5Admin::Krb5Host::Local;
use Krb5Admin::Utils qw/load_krb5hostd_config mk_krb5host_with_config/;

use strict;
use warnings;

{
	package Test::PrestashLocks;

	sub new {
		my ($class) = @_;
		return bless({ realms => [] }, $class);
	}

	sub clear {
		my ($self) = @_;
		$self->{realms} = [];
	}

	sub realms {
		my ($self) = @_;
		return $self->{realms};
	}

	sub run_with_exlock {
		my ($self, $name, $cmd, $host, $client, $realm) = @_;
		push(@{$self->{realms}}, $realm);
	}
}

{
	package Test::ConfiguredPrestashHost;

	sub new {
		my ($class, %args) = @_;
		return bless(\%args, $class);
	}
}

{
	package Test::PrestashHost;

	use base qw/Krb5Admin::Krb5Host::Local/;

	sub get_defrealm { return 'DEFAULT.REALM'; }
	sub reset_krb5ccname { return; }
	sub use_private_krb5ccname { return; }
}

my ($conf_fh, $conf_file) = tempfile('prestash-realms-XXXXXXXX',
    TMPDIR => 1, UNLINK => 1);
print {$conf_fh} <<'EOF';
@prestash_realms = qw(CONFIG.ONE CONFIG.TWO);
1;
EOF
close($conf_fh) or die "close($conf_file): $!";

my %config = (config => $conf_file, config_provided => 1);
load_krb5hostd_config(\%config);
is_deeply($config{prestash_realms}, [qw/CONFIG.ONE CONFIG.TWO/],
    'host configuration loader reads @prestash_realms');

$config{krb5host_class} = 'Test::ConfiguredPrestashHost';
my $configured_host = mk_krb5host_with_config(\%config);
is_deeply($configured_host->{prestash_realms}, [qw/CONFIG.ONE CONFIG.TWO/],
    'host factory passes configured prestash realms to the object');

my $locks = Test::PrestashLocks->new();
my $host = bless({ locks => $locks, myname => 'host.example' },
    'Test::PrestashHost');
$host->internal_set_opt(prestash_realms => $config{prestash_realms});
is_deeply($host->{prestash_realms}, [qw/CONFIG.ONE CONFIG.TWO/],
    'local host object accepts configured prestash realms');

$host->fetch_tickets();
is_deeply($locks->realms(), [qw/CONFIG.ONE CONFIG.TWO/],
    'configured realms are used when fetch has no arguments');

$locks->clear();
$host->fetch_tickets(qw/EXPLICIT.ONE EXPLICIT.TWO/);
is_deeply($locks->realms(), [qw/EXPLICIT.ONE EXPLICIT.TWO/],
    'explicit fetch arguments override configured realms');

$locks->clear();
$host->internal_set_opt(prestash_realms => []);
$host->fetch_tickets();
is_deeply($locks->realms(), ['DEFAULT.REALM'],
    'empty configured realm list preserves default-realm behavior');

done_testing();
