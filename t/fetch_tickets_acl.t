#!/usr/pkg/bin/perl

use DBI;
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
my $destination = 'ASGARD.REALM';
my $windows_realm = 'WINDOWS.REALM';

sub make_db {
	my (%args) = @_;
	my $host = $args{host} // 'host.example';
	my $host_realm = $args{host_realm} // $windows_realm;
	my $kind = $args{kind} // 'windows_ad';
	my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '', {
		RaiseError => 1,
	});

	$dbh->do('CREATE TABLE hosts (name VARCHAR, realm VARCHAR)');
	$dbh->do('CREATE TABLE realms (realm VARCHAR, remote_kind VARCHAR)');
	$dbh->do('CREATE TABLE realm_trusts (' .
	    'realm VARCHAR, trusted_realm VARCHAR)');
	$dbh->do('INSERT INTO hosts VALUES (?, ?)', undef, $host, $host_realm);
	$dbh->do('INSERT INTO realms VALUES (?, ?)', undef,
	    $windows_realm, $kind);
	$dbh->do('INSERT INTO realms VALUES (?, NULL)', undef, $destination);
	$dbh->do('INSERT INTO realm_trusts VALUES (?, ?)', undef,
	    $destination, $windows_realm) if !$args{no_trust};

	return bless({
		client => $args{client},
		ctx => $ctx,
		dbh => $dbh,
		hosts => {$host => {realm => $host_realm}},
	}, 'Test::FetchTicketsACL');
}

sub fetch_acl {
	my (%args) = @_;
	my $host = $args{host} // 'host.example';
	my $db = make_db(%args, host => $host);

	return $db->KHARON_ACL_fetch_tickets('fetch_tickets',
	    $destination, $host);
}

is(fetch_acl(client => 'HOST$@WINDOWS.REALM'), 1,
    'first Windows host is allowed');
is(fetch_acl(
	client => 'SECOND$@WINDOWS.REALM',
	host => 'second.example',
), 1, 'second Windows host is allowed without configuration');

is(fetch_acl(client => 'OTHER$@WINDOWS.REALM'), 1,
    'Windows realm machine account is allowed');
ok(!defined(fetch_acl(
	client => 'HOST$@WINDOWS.REALM',
	kind => 'unix',
)), 'machine account from a non-Windows realm is denied');
ok(!defined(fetch_acl(
	client => 'HOST$@WINDOWS.REALM',
	no_trust => 1,
)), 'untrusted Windows realm is denied');

my $db = make_db(
	client => 'LOCALHOST$@WINDOWS.REALM',
	host => 'localhost',
);
is($db->acl_keytab('create', "host/localhost\@$destination"), 1,
    'Windows machine account may bootstrap its host key');

done_testing();
