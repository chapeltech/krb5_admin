#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

sub contents {
	my ($path) = @_;
	open(my $fh, '<', $path) or die "open $path: $!";
	local $/;
	return <$fh>;
}

my $target = contents('systemd/krb5-hostd.target');
like($target, qr/^Wants=.*\bkrb5-hostd\.socket\b/m,
    'host target wants the local socket');
like($target, qr/^Wants=.*\bkrb5-hostd-knc\.socket\b/m,
    'host target wants the KNC socket');
like($target, qr/^Wants=.*\bkrb5-prestash-refresh\.timer\b/m,
    'host target wants scheduled refresh');

for my $socket (qw/krb5-hostd.socket krb5-hostd-knc.socket/) {
	my $unit = contents("systemd/$socket");
	like($unit, qr/^PartOf=krb5-hostd\.target$/m,
	    "$socket belongs to the host target");
}

my $timer = contents('systemd/krb5-prestash-refresh.timer');
like($timer, qr/^Unit=krb5-prestash-refresh\.service$/m,
    'refresh timer starts the refresh service');
like($timer, qr/^WantedBy=timers\.target$/m,
    'refresh timer can be enabled independently');

is(contents('systemd/80-krb5-hostd.preset'),
    "enable krb5-hostd.target\n", 'host role preset enables its target');
is(contents('systemd/80-krb5-prestash-refresh.preset'),
    "enable krb5-prestash-refresh.timer\n",
    'refresh role preset enables its timer');

ok(!-e 'systemd/krb5-prestash.timer', 'old timer name is absent');
ok(!-e 'systemd/krb5-prestash.service', 'old service name is absent');

done_testing();
