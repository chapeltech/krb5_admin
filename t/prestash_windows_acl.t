#!/usr/pkg/bin/perl

use Test::More;

use Krb5Admin::C;
use Krb5Admin::KerberosDB;

use strict;
use warnings;

{
	package Test::PrestashWindowsDB;

	use base qw/Krb5Admin::KerberosDB/;

	sub query_host {
		my ($self, $host) = @_;
		return $self->{test_hosts}->{$host};
	}
}

my $fqdn = 'machine.example.com';
my $destination = 'ASGARD.REALM';
my $windows_realm = 'WINDOWS.REALM';
my $target = "host/$fqdn\@$destination";
my $ctx = Krb5Admin::C::krb5_init_context();

sub make_db {
	my (%args) = @_;

	return bless({
	    ctx => $ctx,
	    client => $args{client} // "MACHINE\$\@$windows_realm",
	    test_hosts => {
		$fqdn => {realm => $args{host_realm} // $windows_realm},
	    },
	    win_xrealm_bootstrap => $args{mapping} // {
		"machine\$\@$windows_realm" => [$target],
	    },
	}, 'Test::PrestashWindowsDB');
}

my $db = make_db();
is($db->KHARON_ACL_fetch_tickets('fetch_tickets', $destination, $fqdn),
    1, 'exact canonicalized Windows mapping is authorized');

$db = make_db(mapping => {});
ok(!defined($db->KHARON_ACL_fetch_tickets('fetch_tickets', $destination,
    $fqdn)), 'missing Windows mapping is denied');

$db = make_db(mapping => {
    "machine\$\@$windows_realm" =>
    ["host/other.example.com\@$destination"],
});
ok(!defined($db->KHARON_ACL_fetch_tickets('fetch_tickets', $destination,
    $fqdn)), 'wrong Windows target mapping is denied');

$db = make_db(host_realm => 'OTHER.REALM');
ok(!defined($db->KHARON_ACL_fetch_tickets('fetch_tickets', $destination,
    $fqdn)), 'mismatched administrative host realm is denied');

$db = make_db();
ok(!defined($db->KHARON_ACL_fetch_tickets('fetch_tickets', $destination)),
    'Windows machine client must provide its FQDN explicitly');

$db = make_db(client => "host/$fqdn\@$windows_realm", mapping => {});
is($db->KHARON_ACL_fetch_tickets('fetch_tickets', $destination), 1,
    'normal host principal behavior is unchanged');
is($db->KHARON_ACL_fetch_tickets('fetch_tickets', $destination, $fqdn), 1,
    'normal host principal accepts its explicit FQDN');

$db = make_db(client => "host/other.example.com\@$windows_realm",
    mapping => {});
ok(!defined($db->KHARON_ACL_fetch_tickets('fetch_tickets', $destination,
    $fqdn)), 'normal host principal cannot name another host');

$db = make_db(client => "user\@$windows_realm");
ok(!defined($db->KHARON_ACL_fetch_tickets('fetch_tickets', $destination,
    $fqdn)), 'ordinary one-component principal is denied');

$db = make_db(client => "service/MACHINE\$\@$windows_realm");
ok(!defined($db->KHARON_ACL_fetch_tickets('fetch_tickets', $destination,
    $fqdn)), 'multi-component Windows machine principal is denied');

done_testing();
