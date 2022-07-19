##
# Test for timeout functionality of permabit perlunit tests
#
# $Id$
##
package testcases::TimeoutDummyTest;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Log::Log4perl;
use Permabit::Assertions qw(assertNumArgs);
use Permabit::RSVPer;
use Permabit::Utils qw(reallySleep);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

##
# @paramList{new}
our %PROPERTIES =
  (
   # @ple Overrides the rsvp sleep time.
   secondsRsvpSleep => 0,
   # @ple A test-set amount of time to sleep in setup.
   setupSleep       => 0,
   # @ple A test-set amount of time to sleep in tear_down.
   tearDownSleep    => 0,
   # @ple A test-set amount of time to sleep.
   testSleep        => 0,
  );
##

######################################################################
##
sub set_up {
  my ($self) = assertNumArgs(1, @_);
  $self->{rsvper} = Permabit::DummyRSVPer->new(%{$self});
  $log->debug("Created fake RSVPer");
  if ($self->{setupSleep}) {
    $log->debug("Sleeping during set_up: $self->{setupSleep}s");
    reallySleep($self->{setupSleep});
    $log->debug("Done set_up sleep");
  }
}

######################################################################
##
sub tear_down {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{tearDownSleep}) {
    $log->debug("Sleeping during tear_down: $self->{tearDownSleep}s");
    reallySleep($self->{tearDownSleep});
    $log->debug("Done tear_down sleep");
  }
}

######################################################################
##
sub testDummy {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{testSleep}) {
    $log->debug("Sleeping during during the test: $self->{testSleep}s");
    reallySleep($self->{testSleep});
    $log->debug("Done sleeping");
  }
}

######################################################################
######################################################################
##
package Permabit::DummyRSVPer;
use strict;
use warnings FATAL => qw(all);
use Permabit::Assertions qw(assertNumArgs assertDefined);
use Data::Dumper;
use base qw(Permabit::RSVPer);

#########################################################################
# @inherit
##
sub getSecondsSlept {
  my ($self) = assertNumArgs(1, @_);
  assertDefined($self->{secondsRsvpSleep});
  return $self->{secondsRsvpSleep};
}

1;
