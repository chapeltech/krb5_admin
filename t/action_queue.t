#!/usr/pkg/bin/perl

use Test::More tests => 15;

use DBI;
use Krb5Admin::KerberosDB;

use strict;
use warnings;

sub new_db {
	my ($with_actions) = @_;
	my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '', {
		RaiseError => 1, PrintError => 0, AutoCommit => 1,
	});

	$dbh->do(qq{
		CREATE TABLE hosts (
			name VARCHAR PRIMARY KEY,
			is_logical BOOLEAN
		)
	});
	$dbh->do(qq{
		CREATE TABLE hostmap (
			logical VARCHAR,
			physical VARCHAR,
			PRIMARY KEY (logical, physical)
		)
	});
	$dbh->do(qq{
		CREATE TABLE prestashed (
			principal VARCHAR,
			host VARCHAR,
			PRIMARY KEY (principal, host)
		)
	});
	return $dbh if !$with_actions;

	$dbh->do(qq{
		CREATE TABLE actions (
			action_id INTEGER PRIMARY KEY AUTOINCREMENT,
			action_type VARCHAR NOT NULL,
			target_type VARCHAR NOT NULL,
			target_name VARCHAR NOT NULL,
			state VARCHAR NOT NULL DEFAULT 'queued',
			attempts INTEGER NOT NULL DEFAULT 0,
			not_before INTEGER,
			created_at INTEGER NOT NULL DEFAULT
			    (CAST(strftime('%s','now') AS INTEGER)),
			updated_at INTEGER NOT NULL DEFAULT
			    (CAST(strftime('%s','now') AS INTEGER)),
			claimed_at INTEGER,
			completed_at INTEGER,
			last_error VARCHAR,
			payload VARCHAR
		)
	});
	$dbh->do(qq{
		CREATE UNIQUE INDEX actions_queued_unique
		    ON actions(action_type, target_type, target_name)
		 WHERE state = 'queued'
	});
	return $dbh;
}

sub seed_prestash {
	my ($dbh) = @_;

	for my $row (
	    ['cluster.example.com', 1],
	    ['node1.example.com', 0],
	    ['node2.example.com', 0],
	    ['direct.example.com', 0]) {
		$dbh->do('INSERT INTO hosts(name,is_logical) VALUES (?,?)',
		    undef, @$row);
	}
	for my $node (qw/node1.example.com node2.example.com/) {
		$dbh->do('INSERT INTO hostmap(logical,physical) VALUES (?,?)',
		    undef, 'cluster.example.com', $node);
	}
	for my $host (qw/cluster.example.com direct.example.com/) {
		$dbh->do('INSERT INTO prestashed(principal,host) VALUES (?,?)',
		    undef, 'service@EXAMPLE.COM', $host);
	}
}

sub queued_targets {
	my ($dbh) = @_;
	return $dbh->selectcol_arrayref(qq{
		SELECT target_name FROM actions
		 WHERE action_type = 'deliver_prestash'
		   AND target_type = 'host' AND state = 'queued'
		 ORDER BY target_name
	});
}

my $dbh = new_db(1);
seed_prestash($dbh);

my $network_calls = 0;
{
	no warnings qw(redefine once);
	local *Krb5Admin::NotifyClient::notify_update_required = sub {
		$network_calls++;
		die "network notification must not run";
	};

	my $local = bless({dbh => $dbh, local => 1},
	    'Krb5Admin::KerberosDB');
	is($local->refresh_ticket('service@EXAMPLE.COM',
	    'cluster.example.com', 'direct.example.com'), undef,
	    'local mutation returns after enqueue');
	is_deeply(queued_targets($dbh), [qw/
	    direct.example.com node1.example.com node2.example.com/],
	    'logical hosts enqueue current physical members');

	my $remote = bless({dbh => $dbh, local => 0},
	    'Krb5Admin::KerberosDB');
	is($remote->refresh_ticket('service@EXAMPLE.COM',
	    'cluster.example.com', 'direct.example.com'), undef,
	    'remote mutation returns after enqueue');
	is(scalar(@{queued_targets($dbh)}), 3,
	    'duplicate notifications coalesce');
}
is($network_calls, 0, 'local and remote mutations make no network contact');

my $running = $dbh->selectrow_hashref(qq{
	SELECT * FROM actions WHERE target_name = 'node1.example.com'
});
$dbh->do("UPDATE actions SET state = 'running' WHERE action_id = ?",
	undef, $running->{action_id});
my $remote = bless({dbh => $dbh, local => 0}, 'Krb5Admin::KerberosDB');
is($remote->refresh_ticket('service@EXAMPLE.COM',
    'cluster.example.com'), undef,
    'mutation while delivery runs still returns after enqueue');
is($dbh->selectrow_array(qq{
	SELECT count(*) FROM actions
	 WHERE target_name = 'node1.example.com' AND state = 'running'
}), 1, 'running delivery remains independently observable');
is($dbh->selectrow_array(qq{
	SELECT count(*) FROM actions
	 WHERE target_name = 'node1.example.com' AND state = 'queued'
}), 1, 'mutation during delivery creates one follow-up action');

my $old = new_db(0);
$old->begin_work();
$old->do('INSERT INTO prestashed(principal,host) VALUES (?,?)', undef,
    'service@EXAMPLE.COM', 'legacy.example.com');
my $legacy = bless({dbh => $old, local => 0}, 'Krb5Admin::KerberosDB');
my $error;
eval { $legacy->refresh_ticket('service@EXAMPLE.COM',
    'legacy.example.com'); };
$error = $@;
ok($error, 'missing action schema fails the mutation');
like($error, qr/Durable prestash action queue schema is unavailable/,
    'missing schema failure explains the Bifrost compatibility requirement');
ok(!$old->{AutoCommit}, 'failed enqueue leaves the mutation transaction open');
$old->rollback();
is($old->selectrow_array('SELECT count(*) FROM prestashed'), 0,
    'caller rollback closes the mutation/enqueue gap');

is($dbh->selectrow_array(qq{
	SELECT count(*) FROM actions WHERE state = 'queued'
}), 3, 'only one queued action exists per target');
is($dbh->selectrow_array(qq{
	SELECT count(*) FROM actions WHERE action_type = 'deliver_prestash'
}), 4, 'queued follow-up is durable alongside running work');
ok(!grep({ $_ eq 'Krb5Admin/NotifyClient.pm' } keys(%INC)),
    'notification paths do not load the legacy KNC client');

exit(0);
