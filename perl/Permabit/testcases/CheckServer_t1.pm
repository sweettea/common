##
# Test the Permabit::RSVP module
#
# $Id$
##
package testcases::CheckServer_t1;

use strict;
use warnings FATAL => qw(all);
use Carp qw(croak);
use English qw(-no_match_vars);

use Log::Log4perl;
use Permabit::Assertions qw(assertNumArgs);
use Permabit::SystemUtils qw(assertSystem);
use Permabit::Utils qw(getScamVar);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my @SERVERS = ();
if (!(!!getScamVar("DEVVM"))) {
  push(@SERVERS, qw(rsvp jenkins));
} elsif ($ENV{PRSVP_HOST}) {
  push(@SERVERS, $ENV{PRSVP_HOST});
} else {
  croak("environment variable PRSVP_HOST must be set to rsvp server");
}

#############################################################################
##
sub testCheckServer {
  my ($self) = assertNumArgs(1, @_);
  my $bin = "$self->{nfsShareDir}/src/perl/bin";
  my $checkServer = "$bin/checkServer.pl";
  my $verifyScript = "$bin/checkFarms.pl";
  for my $server (@SERVERS) {
    assertSystem("env PRSVP_HOST=$server $verifyScript --exec $checkServer");
  }
}

1;
