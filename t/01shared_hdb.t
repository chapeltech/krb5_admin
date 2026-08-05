#!/usr/pkg/bin/perl
#

use Test::More;

use DBI;
use File::Temp qw(tempdir);
use Scalar::Util qw(refaddr);
use Sys::Hostname;

use Krb5Admin::C;
use Krb5Admin::KerberosDB;

use strict;
use warnings;

plan skip_all => 'shared SQLite HDB support is not available'
    if !Krb5Admin::C->can('krb5_get_kadm5_hndl_dbi_sqlite');

{
    package Krb5Admin::KerberosDB::SharedHDBReconnectTest;

    our @ISA = qw(Krb5Admin::KerberosDB);

    sub KHARON_MASTER { return 'not-the-local-host'; }
}

my $dir = tempdir(CLEANUP => 1);
my $db = "$dir/shared-hdb.db";
my $conf = "$dir/krb5.conf";
my $hostname = hostname();

open(my $in, '<', 't/krb5.conf.in') or die "open krb5.conf.in: $!";
open(my $out, '>', $conf) or die "open $conf: $!";
while (my $line = <$in>) {
    $line =~ s/__HOSTNAME__/$hostname/g;
    print $out $line;
}
close($out) or die "close $conf: $!";
close($in) or die "close krb5.conf.in: $!";

$ENV{KRB5_CONFIG} = $conf;

my $dbh = DBI->connect("dbi:SQLite:$db", "", "",
    {RaiseError => 1, PrintError => 0, AutoCommit => 1,
    sqlite_use_immediate_transaction => 0});
$dbh->do("PRAGMA foreign_keys = ON");
$dbh->do("PRAGMA journal_mode = WAL");

my $ctx = Krb5Admin::C::krb5_init_context();
my $hndl = Krb5Admin::C::krb5_get_kadm5_hndl_dbi_sqlite(
    $ctx, "sqlite:$db", undef, $dbh, 1);
ok($hndl, 'opened kadm5 with a caller-owned SQLite handle');

Krb5Admin::C::init_kdb($ctx, $hndl);

my ($tables) = $dbh->selectrow_array(q{
    SELECT count(*) FROM sqlite_master
    WHERE type = 'table' AND name IN ('Version', 'Principal', 'Entry')
});
is($tables, 3, 'created the Heimdal HDB schema on the caller handle');

$dbh->do(q{
    CREATE TRIGGER hdb_fail_principal
    BEFORE INSERT ON Principal
    WHEN NEW.principal LIKE 'atomicity-failure%'
    BEGIN
        SELECT RAISE(ABORT, 'injected principal failure');
    END
});

my ($entries_before) = $dbh->selectrow_array('SELECT count(*) FROM Entry');
my ($principals_before) =
    $dbh->selectrow_array('SELECT count(*) FROM Principal');
my $created = eval {
    Krb5Admin::C::krb5_createkey($ctx, $hndl,
        'atomicity-failure@TEST.REALM', []);
    1;
};
ok(!$created, 'injected HDB write failure was returned to the caller');
is($dbh->selectrow_array('SELECT count(*) FROM Entry'), $entries_before,
    'failed HDB write left no Entry row');
is($dbh->selectrow_array('SELECT count(*) FROM Principal'),
    $principals_before, 'failed HDB write left no Principal row');
$dbh->do('DROP TRIGGER hdb_fail_principal');

$dbh->{sqlite_use_immediate_transaction} = 1;
$dbh->begin_work();
$dbh->do('SELECT 1');
is($dbh->sqlite_get_autocommit(), 0,
    'caller started the native SQLite transaction');
my $transaction_principal = 'outer-transaction@TEST.REALM';
my $transaction_create = eval {
    Krb5Admin::C::krb5_createkey($ctx, $hndl, $transaction_principal, []);
    1;
};
ok($transaction_create, 'created a principal inside the caller transaction')
    or diag($@);
is($dbh->selectrow_array(
        'SELECT count(*) FROM Principal WHERE principal = ?', undef,
        $transaction_principal),
    1, 'HDB write is visible inside the caller transaction');
$dbh->rollback();
is($dbh->selectrow_array(
        'SELECT count(*) FROM Principal WHERE principal = ?', undef,
        $transaction_principal),
    0, 'caller rollback includes the complete HDB write');
$dbh->{sqlite_use_immediate_transaction} = 0;

Krb5Admin::C::kadm5_destroy($hndl);
$dbh->disconnect();

my $provided_db = "$dir/provided.db";
my $provided_dbh = DBI->connect("dbi:SQLite:$provided_db", "", "",
    {RaiseError => 1, PrintError => 0, AutoCommit => 1});
ok(-e $provided_db, 'DBI created the caller-provided SQLite file');
my $provided_kdb = eval {
    Krb5Admin::KerberosDB->new(
        local => 1,
        dbh => $provided_dbh,
        dbname => "sqlite:$provided_db",
        sqlite => $provided_db,
        sqlite_shared_hdb => 1,
    );
};
ok($provided_kdb, 'initialized HDB schema on a fresh caller-provided DBH')
    or diag($@);
is($provided_dbh->selectrow_array(q{
        SELECT count(*) FROM sqlite_master
        WHERE type = 'table' AND name IN ('Version', 'Principal', 'Entry')
    }), 3, 'caller-provided DBH contains the complete HDB schema');
$provided_kdb->disconnect_kadm5() if $provided_kdb;
$provided_dbh->disconnect();

my $reconnect_db = "$dir/reconnect.db";
my $reconnect_kdb =
    Krb5Admin::KerberosDB::SharedHDBReconnectTest->new(
        local => 1,
        dbname => "sqlite:$reconnect_db",
        sqlite => $reconnect_db,
    );
Krb5Admin::C::init_kdb($reconnect_kdb->{ctx}, $reconnect_kdb->{hndl});
my $old_dbh = $reconnect_kdb->get_dbh();
my $reconnected = eval { $reconnect_kdb->reconnect_sqlite(); 1 };
ok($reconnected, 'reconnected SQLite with a shared HDB handle') or diag($@);
isnt(refaddr($reconnect_kdb->get_dbh()), refaddr($old_dbh),
    'reconnect replaced the DBI handle');
my $after_reconnect = eval {
    Krb5Admin::C::krb5_createkey($reconnect_kdb->{ctx},
        $reconnect_kdb->{hndl}, 'after-reconnect@TEST.REALM', []);
    1;
};
ok($after_reconnect, 'replacement kadm5 handle uses the replacement DBH')
    or diag($@);
$reconnect_kdb->disconnect_kadm5();
$reconnect_kdb->get_dbh()->disconnect();

done_testing();
