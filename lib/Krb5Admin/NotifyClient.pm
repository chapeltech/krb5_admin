#
#

package Krb5Admin::NotifyClient;

use Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw{ notify_update_required };

use File::Temp qw(tempfile);
use Sys::Hostname qw(hostname);

use Krb5Admin::C;
use Krb5Admin::Krb5Host::Client;

sub notify_host {
	my ($krb5, $host) = @_;
	my $hdef = $krb5->query_host($host);

	#
	# Short-circuit if the host principal doesn't exist.  This
	# means that the host hasn't yet been bootstrapped.  We delay
	# this test until this function as in previous opportunities,
	# we might be dealing with a cluster name for which we would
	# not expect to find a host princ.

	return if !defined($hdef);
	eval { $krb5->query("host/$host\@$hdef->{realm}"); };
	return if $@;

	my ($ccfh, $ccfile) = tempfile('krb5-admin-notify-XXXXXXXX',
	    TMPDIR => 1, UNLINK => 1);
	close($ccfh) or die "Can't close $ccfile: $!\n";
	local $ENV{KRB5CCNAME} = "FILE:$ccfile";
	my $princ = 'krb5_admin/' . hostname() . '@' . $hdef->{realm};
	Krb5Admin::C::kinit_kt($krb5->{ctx}, $princ, undef,
	    $ENV{KRB5CCNAME});

	my $clnt = Krb5Admin::Krb5Host::Client->new($host);
	$clnt->do_update();
}

sub notify_update_required {
	my ($krb5, $host) = @_;
	my $hdef = $krb5->query_host($host);
	if ($hdef->{is_logical}) {
		my $hostmaps = $krb5->query_hostmap($host);
		for my $hmap (@$hostmaps) {
			notify_host($krb5, $hmap);
		}
	} else {
		notify_host($krb5, $host);
	}
}

1;
