#
# Blame: "Roland C. Dowdeswell" <elric@imrryr.org>

package Krb5Admin::ActionQueue;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(enqueue_prestash_delivery);

use strict;
use warnings;

sub _schema_error {
	my ($error) = @_;

	$error =~ s/\s+$/ /;
	die "Durable prestash action queue schema is unavailable or " .
	    "incompatible. Start an upgraded Bifrost kdcd against the shared " .
	    "adjunct SQLite database before retrying this mutation: $error";
}

sub _require_schema {
	my ($dbh) = @_;

	eval {
		my $sth = $dbh->prepare(qq{
			SELECT action_id, action_type, target_type, target_name,
			       state, attempts, not_before, created_at, updated_at,
			       claimed_at, completed_at, last_error, payload
			  FROM actions WHERE 1 = 0
		});
		$sth->execute();
	};
	_schema_error($@) if $@;
	return;
}

sub enqueue_prestash_delivery {
	my ($dbh, @hosts) = @_;
	my %seen;

	@hosts = grep { defined($_) && !$seen{$_}++ } map { lc($_) } @hosts;
	return 0 if !@hosts;

	_require_schema($dbh);
	my $queued = 0;
	for my $host (@hosts) {
		eval {
			my $rows = $dbh->do(qq{
				INSERT INTO actions (
					action_type, target_type, target_name,
					state, updated_at
				)
				SELECT DISTINCT 'deliver_prestash', 'host', target,
				       'queued', CAST(strftime('%s','now') AS INTEGER)
				  FROM (
					SELECT physical AS target
					  FROM hostmap WHERE logical = ?
					UNION
					SELECT ? AS target
					 WHERE COALESCE((SELECT is_logical FROM hosts
					                  WHERE name = ?), 0) = 0
				  )
				 WHERE target IS NOT NULL
				ON CONFLICT(action_type, target_type, target_name)
				WHERE state = 'queued' DO UPDATE SET
					updated_at = excluded.updated_at,
					not_before = NULL,
					completed_at = NULL,
					last_error = NULL
			}, undef, $host, $host, $host);
			$queued += $rows if defined($rows) && $rows > 0;
		};
		_schema_error($@) if $@;
	}

	return $queued;
}

1;
