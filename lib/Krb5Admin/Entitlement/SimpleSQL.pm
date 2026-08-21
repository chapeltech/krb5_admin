package Krb5Admin::Entitlement::SimpleSQL;

use base qw/Kharon::Entitlement::SimpleSQL/;

use Kharon::dbutils qw/sql_command/;

use strict;
use warnings;

sub check1 {
	my ($self, $verb) = @_;
	my $ret = $self->SUPER::check1($verb);

	return $ret if defined($ret) || @{$self->{credlist}} == 0;

	my $dbh = $self->{dbh};
	my $table = $self->{table};
	my $subject = $self->{credlist}->[0];
	my $sth = sql_command($dbh, qq{
		WITH RECURSIVE groups(name) AS (
			SELECT aclgroup FROM aclgroups WHERE acl = ?
			UNION
			SELECT aclgroup FROM aclgroups, groups
			    WHERE aclgroups.acl = groups.name
		)
		SELECT COUNT(verb) FROM $table, groups
		    WHERE subject = groups.name AND verb = ?
	}, $subject, $verb);

	$ret = $sth->fetch()->[0];
	return $ret ? 1 : undef;
}

1;
