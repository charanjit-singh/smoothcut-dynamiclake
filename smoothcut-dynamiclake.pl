#!/usr/bin/perl
# SmoothCut for DynamicLake -- the plugin's executable.
#
# DynamicLake starts this with DYNAMICLAKE_JSON_SOCKET set. It is a relay and nothing else: the
# bytes DynamicLake sends go to SmoothCut, and the bytes SmoothCut sends go to DynamicLake.
# Everything that decides what the notch shows lives in SmoothCut (electron/dynamiclake), so there
# is one implementation of it and this file has no logic to get wrong.
#
# DynamicLake only trusts the process it launched: a message from any other process, even a child
# of this one, is answered "Client is not trusted." So this one process holds both connections
# itself. Perl is used because every Mac has it (/usr/bin/perl) and it can, unlike /bin/sh; there
# is no Python or Node to rely on.
#
# SmoothCut offers a local socket only while Settings > Notch > "Show in the notch" is on. While it
# is not there, this waits quietly: no connection to DynamicLake is made, so nothing is shown, and
# nothing is printed except on a real fault. When SmoothCut goes away, the DynamicLake connection
# is closed too, which takes its activity down, and the wait starts again.
#
# The installed plugin package is never written to.

use strict;
use warnings;
use IO::Socket::UNIX;
use IO::Select;
use Socket qw(SOCK_STREAM);

my $dl_path = $ENV{DYNAMICLAKE_JSON_SOCKET} // "";
if ($dl_path eq "") {
	print STDERR "DYNAMICLAKE_JSON_SOCKET is not set. Start this plugin from DynamicLake.\n";
	exit 2;
}

# The feature list DynamicLake supports ("numericText,presentSneakPeek,..."), passed on so
# SmoothCut only sends what this DynamicLake understands. Letters and commas only.
(my $features = $ENV{DYNAMICLAKE_PLUGIN_FEATURES} // "") =~ s/[^A-Za-z,]//g;

# Seconds between looks for SmoothCut while it is not there. SMOOTHCUT_RELAY_POLL is for tests.
my $poll = $ENV{SMOOTHCUT_RELAY_POLL} // 2;

$SIG{TERM} = $SIG{INT} = $SIG{HUP} = sub { exit 0 };
$SIG{PIPE} = "IGNORE";

# Where SmoothCut says its socket is. Both folder names are tried because an install that could
# not migrate from the old product name keeps the old folder. SMOOTHCUT_DATA_DIR is for tests.
sub find_socket {
	my $home = $ENV{HOME} // "";
	for my $dir ($ENV{SMOOTHCUT_DATA_DIR}, "$home/Library/Application Support/SmoothCut", "$home/Library/Application Support/Smooth Cut") {
		next unless defined $dir && $dir ne "";
		open(my $fh, "<", "$dir/dynamiclake-endpoint") or next;
		my $path = <$fh>;
		close $fh;
		next unless defined $path;
		chomp $path;
		return $path if -S $path;
	}
	return undef;
}

sub connect_to {
	my ($path) = @_;
	return IO::Socket::UNIX->new(Type => SOCK_STREAM, Peer => $path);
}

# Copies until either side closes. Returns which one did.
sub relay {
	my ($app, $dl) = @_;
	my $select = IO::Select->new($app, $dl);
	while (1) {
		for my $from ($select->can_read) {
			my $to = $from == $app ? $dl : $app;
			my $n = sysread($from, my $buffer, 65536);
			return $from == $app ? "app" : "dynamiclake" unless $n;
			my $off = 0;
			while ($off < $n) {
				my $w = syswrite($to, $buffer, $n - $off, $off);
				return $to == $app ? "app" : "dynamiclake" unless defined $w;
				$off += $w;
			}
		}
	}
}

while (1) {
	# DynamicLake itself went away: nothing left to relay to.
	exit 0 unless -S $dl_path;
	my $app_path = find_socket();
	if (defined $app_path) {
		my $app = connect_to($app_path);
		if ($app) {
			syswrite($app, "SMOOTHCUT-DYNAMICLAKE 1 $features\n");
			my $dl = connect_to($dl_path) or exit 0;
			my $closed = relay($app, $dl);
			close $app;
			close $dl;
			exit 0 if $closed eq "dynamiclake";
		}
	}
	select(undef, undef, undef, $poll);
}
