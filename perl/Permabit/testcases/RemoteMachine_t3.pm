##
# Test the Permabit::RemoteMachine module when a long running command is
# interrupted by the nightly timeout mechanism.
#
# $Id$
##
package testcases::RemoteMachine_t3;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Log::Log4perl;
use Permabit::Assertions qw(assertEqualNumeric assertNENumeric assertNumArgs);
use Permabit::AsyncSub;

use base qw(testcases::RemoteMachineBase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

###############################################################################
##
sub testTimeout {
  my ($self) = assertNumArgs(1, @_);

  # Since RSVP just gave us the machine, it passes checkserver.  So we expect
  # that the only bash we are running on it is because of our RemoteMachine,
  # and we expect that we are not running any sleep commands.
  my @myBashPids = $self->_myPgrep("bash");
  assertEqualNumeric(1, scalar(@myBashPids));
  my ($bashPid) = @myBashPids;
  assertEqualNumeric(0, scalar($self->_myPgrep("sleep")));

  # Start an AsyncSub that will send us a SIGUSR2 in 3 seconds.  Then sleep for
  # a full minute.  This will simulate the nightly code killing the test at 2PM
  # while a RemoteMachine is running a long command that neither reads from nor
  # writes to the socket.
  my $timer = Permabit::AsyncSub->new(code => \&_sleepAndTimeout);
  $timer->start();
  eval { $self->{machine}->sendCommand("sleep 60"); };
  $log->warn($EVAL_ERROR);
  $timer->result();

  # Now when we reset the session, there is a real problem if the original
  # BashSession is still alive, or if the sleep is still running.
  $self->{machine}->resetSession();
  @myBashPids = $self->_myPgrep("bash");
  assertEqualNumeric(1, scalar(@myBashPids));
  assertNENumeric($bashPid, $myBashPids[0]);
  assertEqualNumeric(0, scalar($self->_myPgrep("sleep")));
}

###############################################################################
# Find all the instances of the named program being run by the current user on
# the RemoteMachine.
#
# @param name  The name of the program.
#
# @return the list of IDs of the processes running the program.
##
sub _myPgrep {
  my ($self, $name) = assertNumArgs(2, @_);
  $self->{machine}->sendCommand("pgrep $name -u $self->{user}");
  my @pids = split(qr/\s+/, $self->{machine}->getStdout());
  $log->info("My $name pids: @pids");
  return @pids;
}

###############################################################################
# Sleep for 3 seconds and then send a SIGUSR2 to our parent.  This runs in an
# AsyncSub and is therefore sending the SIGUSR2 to the test process.
##
sub _sleepAndTimeout {
  sleep(3);
  kill("USR2", getppid());
}

1;
