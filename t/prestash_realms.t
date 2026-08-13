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
		return bless({ requests => [] }, $class);
	}

	sub clear {
		my ($self) = @_;
		$self->{requests} = [];
	}

	sub requests {
		my ($self) = @_;
		return $self->{requests};
	}

	sub run_with_exlock {
		my ($self, $name, $cmd, $host, $client, $realm, $fqdn) = @_;
		push(@{$self->{requests}}, {
		    client => $client, realm => $realm, host => $fqdn});
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
	package Test::PrestashClient;

	sub new {
		my ($class) = @_;
		return bless({ requests => [] }, $class);
	}

	sub fetch_tickets {
		my ($self, @args) = @_;
		push(@{$self->{requests}}, \@args);
		return {};
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
%prestash_clients = (
	'CONFIG.TWO' => 'MACHINE$@WINDOWS.REALM',
);
1;
EOF
close($conf_fh) or die "close($conf_file): $!";

my %config = (config => $conf_file, config_provided => 1);
load_krb5hostd_config(\%config);
is_deeply($config{prestash_realms}, [qw/CONFIG.ONE CONFIG.TWO/],
    'host configuration loader reads @prestash_realms');
is_deeply($config{prestash_clients},
    {'CONFIG.TWO' => 'MACHINE$@WINDOWS.REALM'},
    'host configuration loader reads %prestash_clients');

$config{krb5host_class} = 'Test::ConfiguredPrestashHost';
my $configured_host = mk_krb5host_with_config(\%config);
is_deeply($configured_host->{prestash_realms}, [qw/CONFIG.ONE CONFIG.TWO/],
    'host factory passes configured prestash realms to the object');
is_deeply($configured_host->{prestash_clients},
    {'CONFIG.TWO' => 'MACHINE$@WINDOWS.REALM'},
    'host factory passes configured prestash clients to the object');

my $locks = Test::PrestashLocks->new();
my $host = bless({
    ctx => Krb5Admin::C::krb5_init_context(),
    locks => $locks,
    myname => 'host.example',
},
    'Test::PrestashHost');
$host->internal_set_opt(prestash_realms => $config{prestash_realms});
$host->internal_set_opt(prestash_clients => $config{prestash_clients});
is_deeply($host->{prestash_realms}, [qw/CONFIG.ONE CONFIG.TWO/],
    'local host object accepts configured prestash realms');

$host->fetch_tickets();
is_deeply($locks->requests(), [
    {client => 'host/host.example', realm => 'CONFIG.ONE',
     host => 'host.example'},
    {client => 'MACHINE$@WINDOWS.REALM', realm => 'CONFIG.TWO',
     host => 'host.example'},
], 'configured realms select per-realm clients');

$locks->clear();
$host->fetch_tickets(qw/EXPLICIT.ONE CONFIG.TWO/);
is_deeply($locks->requests(), [
    {client => 'host/host.example', realm => 'EXPLICIT.ONE',
     host => 'host.example'},
    {client => 'MACHINE$@WINDOWS.REALM', realm => 'CONFIG.TWO',
     host => 'host.example'},
], 'explicit realms override defaults and retain per-realm clients');

$locks->clear();
$host->internal_set_opt(prestash_realms => []);
$host->fetch_tickets();
is_deeply($locks->requests(), [
    {client => 'host/host.example', realm => 'DEFAULT.REALM',
     host => 'host.example'},
],
    'empty configured realm list preserves default-realm behavior');

my $client = Test::PrestashClient->new();
$host->{kmdb} = $client;
$host->fetch_tickets_realm('MACHINE$@WINDOWS.REALM', 'CONFIG.TWO',
    'host.example');
is_deeply($client->{requests}, [['CONFIG.TWO', 'host.example']],
    'remote fetch receives destination realm and explicit local FQDN');

eval {
	$host->internal_set_opt(prestash_clients => {
	    'CONFIG.TWO' => 'host/host.example@WINDOWS.REALM'});
};
like($@, qr/fully qualified Windows machine principal/,
    'non-machine client mapping is rejected');

eval {
	$host->internal_set_opt(prestash_clients => {
	    'CONFIG.TWO' => 'MACHINE$'});
};
like($@, qr/fully qualified Windows machine principal/,
    'unqualified machine client mapping is rejected');

done_testing();
