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
		return bless({ calls => [] }, $class);
	}

	sub clear {
		my ($self) = @_;
		$self->{calls} = [];
	}

	sub calls {
		my ($self) = @_;
		return $self->{calls};
	}

	sub run_with_exlock {
		my ($self, $name, $cmd, $host, $client, $realm) = @_;
		push(@{$self->{calls}}, {
			client => $client,
			realm => $realm,
		});
	}
}

{
	package Test::PrestashKmdb;

	sub new {
		my ($class) = @_;
		return bless({ calls => [] }, $class);
	}

	sub fetch_tickets {
		my ($self, @args) = @_;
		push(@{$self->{calls}}, \@args);
		return {};
	}

	sub calls {
		my ($self) = @_;
		return $self->{calls};
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
@prestash_realms = (
	'CONFIG.ONE',
	{
		realm => 'CONFIG.TWO',
		from_princ => 'hostname$@WINDOWS.REALM',
	},
	'CONFIG.THREE',
);
1;
EOF
close($conf_fh) or die "close($conf_file): $!";

my $configured_realms = [
	'CONFIG.ONE',
	{
		realm => 'CONFIG.TWO',
		from_princ => 'hostname$@WINDOWS.REALM',
	},
	'CONFIG.THREE',
];
my %config = (config => $conf_file, config_provided => 1);
load_krb5hostd_config(\%config);
is_deeply($config{prestash_realms}, $configured_realms,
    'host configuration loader reads @prestash_realms');

$config{krb5host_class} = 'Test::ConfiguredPrestashHost';
my $configured_host = mk_krb5host_with_config(\%config);
is_deeply($configured_host->{prestash_realms}, $configured_realms,
    'host factory passes configured prestash realms to the object');

my $locks = Test::PrestashLocks->new();
my $host = bless({ locks => $locks, myname => 'host.example' },
    'Test::PrestashHost');
$host->internal_set_opt(prestash_realms => $config{prestash_realms});
is_deeply($host->{prestash_realms}, $configured_realms,
    'local host object accepts configured prestash realms');

$host->fetch_tickets();
is_deeply({ map { $_->{realm} => $_ } @{$locks->calls()} }, {
	'CONFIG.ONE' => {
		client => 'host/host.example',
		realm => 'CONFIG.ONE',
	},
	'CONFIG.TWO' => {
		client => 'hostname$@WINDOWS.REALM',
		realm => 'CONFIG.TWO',
	},
	'CONFIG.THREE' => {
		client => 'host/host.example',
		realm => 'CONFIG.THREE',
	},
}, 'configured scalar/hash entries select sources');

$locks->clear();
$host->fetch_tickets(qw/EXPLICIT.ONE CONFIG.TWO/);
is_deeply($locks->calls(), [
	{
		client => 'host/host.example',
		realm => 'EXPLICIT.ONE',
	},
	{
		client => 'hostname$@WINDOWS.REALM',
		realm => 'CONFIG.TWO',
	},
], 'explicit API realms retain configured source principals');

$locks->clear();
$host->internal_set_opt(prestash_realms => []);
$host->fetch_tickets();
is_deeply($locks->calls(), [{
	client => 'host/host.example',
	realm => 'DEFAULT.REALM',
}],
    'empty configured realm list preserves default-realm behavior');

my $remote_kmdb = Test::PrestashKmdb->new();
my @connections;
{
	no warnings 'redefine';
	local *Krb5Admin::Client::new = sub {
		my ($class, $client, $opts) = @_;
		push(@connections, [$client, {%{$opts}}]);
		return $remote_kmdb;
	};

	my $remote_host = bless({
		invoking_user => 'root',
		kadmin => 0,
		local => 0,
	}, 'Test::PrestashHost');
	$remote_host->fetch_tickets_realm('hostname$@WINDOWS.REALM',
	    'CONFIG.TWO');
}
is_deeply(\@connections, [[
	'hostname$@WINDOWS.REALM',
	{ realm => 'CONFIG.TWO' },
]], 'remote client authenticates with the selected source principal');
is_deeply($remote_kmdb->calls(), [[qw/CONFIG.TWO/]],
	'remote fetch receives only the destination realm');

done_testing();
