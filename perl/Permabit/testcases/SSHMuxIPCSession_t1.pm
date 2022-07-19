##
# Test the Permabit::SystemUtils module
#
# $Id$
##
package testcases::SSHMuxIPCSession_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use BSD::Resource;
use Carp qw(croak);
use Data::Dumper;
use Log::Log4perl::Level;
use POSIX qw(:sys_wait_h);
use Permabit::Assertions qw(
  assertDefined
  assertEqualNumeric
  assertEvalErrorMatches
  assertFalse
  assertNumArgs
);
use Permabit::SSHMuxIPCSession;

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

# Turn up logging during testing.
Log::Log4perl->get_logger("Permabit::SSHMuxIPCSession")->level($DEBUG);

######################################################################
##
sub testSigChild {
  my ($self) = assertNumArgs(1, @_);

  # We want to make sure that we are correctly reaping child processes
  # in SSHMux even if there is a CHLD sig-handler (i.e. Proc::Simple).
  # Therefore, by the time our SIGCHLD handler gets called, we want to
  # be sure that there are no children left to reap, which would have
  # meant that SSHMux properly reaped all its children that have
  # finished. We also want to try to check that we are unblocking
  # the SIGCHLD as soon as possible so we keep track of how many times
  # our handler gets called.
  my $count = 0;
  $SIG{CHLD} = sub {
    ++$count;
    $log->debug("signal handler called with: @_");
    my %kidStatus;
    while ((my $child = waitpid(-1,WNOHANG)) > 0) {
      $kidStatus{$child} = $?;
    }
    assertFalse(scalar(%kidStatus),
                "unreaped children: " . Dumper(\%kidStatus));
  };

  # Now that the sig-handlers installed, lets fire off a session and
  # make sure nothing else bad happens.
  my $session = Permabit::SSHMuxIPCSession->new(hostname => 'localhost');
  assertDefined($session, "couldn't create sshmux session");

  # Run a normal session
  assertEqualNumeric(0, scalar($session->send("echo hello world")),
                     "running echo command failed");
  assertEqualNumeric(1, $count, "CHLD signals were not unblocked correctly");

  # Test that we unblock signals even if the command timed out.
  $session->timeout(0.1);
  $session->setErrorHandler(\&_testErrorHandler);
  # Don't litter the directory with ssh core dumps from the child being killed.
  setrlimit(RLIMIT_CORE, 0, 0);
  eval {
    $session->send("echo waiting for timeout ; cat")
  };
  assertEqualNumeric(2, $count, "CHLD signals were not unblocked correctly");
  assertEvalErrorMatches(qr/timeout during command execution/);

  # Tear everything down.
  $session->close();
  assertEqualNumeric(3, $count, "CHLD signals were not unblocked correctly");
  $SIG{CHLD} = undef;
}

######################################################################
# This error handler simply logs the expected error so that the test
# may pass.
##
sub _testErrorHandler {
  $log->debug("Expected error has been caught.");
}

######################################################################
# Test connection timeouts to make sure that nothing is hanging.
##
sub testTimeOut {
  my ($self) = assertNumArgs(1, @_);

  my $session = Permabit::SSHMuxIPCSession->new(
    handler => \&_testErrorHandler,
    hostname => 'this-is-only-a-test');
  if (defined($session)) {
    $session->close();
  }
}

1;
