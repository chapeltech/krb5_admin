#!/usr/pkg/bin/perl

use Test::More tests=> 5;

use Data::Dumper;

use Krb5Admin::ForkClient;

use strict;
use warnings;

sub mk_kmdb {
	Krb5Admin::ForkClient->new({config => './t/krb5_admind.conf'}, @_);
}

my $kmdb;
$ENV{'KRB5_CONFIG'} = './t/krb5.conf';

$kmdb = mk_kmdb(CREDS => 'admin_user@TEST.REALM');

eval {
	$kmdb->add_acl('foo@TEST.REALM', 'krb5');
	$kmdb->add_acl('bar@TEST.REALM', 'krb5');
	$kmdb->add_acl('baz@TEST.REALM', 'krb5');

	$kmdb->sacls_add('create', 'foo@TEST.REALM');
	$kmdb->sacls_add('create', 'bar@TEST.REALM');
	$kmdb->sacls_add('create', 'baz@TEST.REALM');

	$kmdb->sacls_add('sacls_add', 'foo@TEST.REALM');
	$kmdb->sacls_add('sacls_del', 'bar@TEST.REALM');
};

ok(!$@, "Add initial sacls");

$kmdb = mk_kmdb(CREDS => 'foo@TEST.REALM');

eval { $kmdb->sacls_del('create', 'foo@TEST.REALM'); };
ok(!$@, 'foo@TEST.REALM deleting its own create privs.');
diag(Dumper($@)) if $@;

$kmdb = mk_kmdb(CREDS => 'bar@TEST.REALM');

eval { $kmdb->sacls_del('create', 'bar@TEST.REALM'); };
ok(!$@, 'bar@TEST.REALM deleting its own create privs.');
diag(Dumper($@)) if $@;

$kmdb = mk_kmdb(CREDS => 'baz@TEST.REALM');

eval { $kmdb->sacls_del('create', 'baz@TEST.REALM'); };
ok($@, 'baz@TEST.REALM should not be able to relinquish privs...');

eval {
	$kmdb = mk_kmdb(CREDS => 'admin_user@TEST.REALM');
	$kmdb->create_group('sacl-admins',
	    owner => ['admin_user@TEST.REALM']);
	$kmdb->modify_group('sacl-admins',
	    add_member => ['baz@TEST.REALM']);
	$kmdb->sacls_add('create_user', 'sacl-admins');

	$kmdb = mk_kmdb(CREDS => 'baz@TEST.REALM');
	$kmdb->create_user('group-sacl-user@TEST.REALM');
};
ok(!$@, 'group member inherits the group SACL.');
diag(Dumper($@)) if $@;
