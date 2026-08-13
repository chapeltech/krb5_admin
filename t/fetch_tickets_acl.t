#!/usr/pkg/bin/perl

use Test::More;

use Krb5Admin::C;
use Krb5Admin::KerberosDB;

use strict;
use warnings;

{
	package Test::FetchTicketsACL;

	use base qw/Krb5Admin::KerberosDB/;

	sub query_host {
		my ($self, $host) = @_;
		return $self->{hosts}->{$host};
	}
}

my $ctx = Krb5Admin::C::krb5_init_context();
my $fqdn = 'host.example';
my $destination = 'ASGARD.REALM';
my $windows_realm = 'WINDOWS.REALM';
my $target = "host/$fqdn\@$destination";

sub fetch_acl {
	my (%args) = @_;
	my $kmdb = bless({
		client => $args{client},
		ctx => $ctx,
		hosts => $args{hosts} || {
			$fqdn => { realm => $windows_realm },
		},
		win_xrealm_bootstrap => $args{map},
	}, 'Test::FetchTicketsACL');

	return $kmdb->KHARON_ACL_fetch_tickets('fetch_tickets',
	    $args{realm} || $destination,
	    exists($args{host}) ? $args{host} : $fqdn);
}

is(fetch_acl(
	client => 'HOSTNAME$@WINDOWS.REALM',
	map => { 'hostname$@WINDOWS.REALM' => [$target] },
), 1, 'canonical Windows machine account with exact mapping is allowed');

ok(!defined(fetch_acl(
	client => 'hostname$@WINDOWS.REALM',
	host => undef,
	map => { 'hostname$@WINDOWS.REALM' => [$target] },
)), 'Windows machine account cannot imply the target host');

ok(!defined(fetch_acl(
	client => 'hostname$@WINDOWS.REALM',
	map => {},
)), 'missing Windows mapping is denied');

ok(!defined(fetch_acl(
	client => 'hostname$@WINDOWS.REALM',
	map => {
		'hostname$@WINDOWS.REALM' => [
			'host/other.example@ASGARD.REALM',
		],
	},
)), 'mapping for a different host is denied');

ok(!defined(fetch_acl(
	client => 'hostname$@WINDOWS.REALM',
	realm => 'OTHER.REALM',
	map => { 'hostname$@WINDOWS.REALM' => [$target] },
)), 'mapping for a different destination realm is denied');

ok(!defined(fetch_acl(
	client => 'hostname$@WINDOWS.REALM',
	map => { 'hostname$@WINDOWS.REALM' => [$target] },
	hosts => { $fqdn => { realm => 'OTHER.REALM' } },
)), 'host realm mismatch denies Windows machine account');

ok(!defined(fetch_acl(
	client => 'hostname$@WINDOWS.REALM',
	map => { 'hostname$@WINDOWS.REALM' => [$target] },
	hosts => {},
)), 'missing host record denies Windows machine account');

ok(!defined(fetch_acl(
	client => 'hostname@WINDOWS.REALM',
	map => { 'hostname@WINDOWS.REALM' => [$target] },
)), 'one-component principal without dollar suffix is denied');

is(fetch_acl(
	client => "host/$fqdn\@WINDOWS.REALM",
	map => {},
), 1, 'ordinary matching host principal remains allowed');

is(fetch_acl(
	client => "host/$fqdn\@WINDOWS.REALM",
	host => undef,
	map => {},
), 1, 'ordinary host principal still implies its target host');

ok(!defined(fetch_acl(
	client => "host/other.example\@WINDOWS.REALM",
	map => {},
)), 'ordinary host principal cannot fetch for another host');

done_testing();
