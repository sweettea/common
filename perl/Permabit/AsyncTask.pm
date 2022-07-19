###############################################################################
# Provides the ability to asynchronously run perl code and later wait for the
# resulting return value, or error result.  If the operations are killed, a
# teardown method is always called.
#
# @synopsis
#
# Basic usage:
#
#  use Permabit::VDOTask::Operation;
#  my $task = Permabit::VDOTask::Operation->new("message");
#  $task->start();
#  # do other stuff
#  eval { $task->result(); };
#  if ($EVAL_ERROR) {
#    $log->error("backgound task threw $EVAL_ERROR");
#  }
#
#  package Permabit::VDOTask::Operation;
#  use base Permabit::AsyncTask;
#  sub new {
#    my ($invocant, $message) = assertNumArgs(2, @_);
#    my $self = $invocant::SUPER->new();
#    $self->{message} = $message;
#    return $self;
#  }
#  sub taskCode {
#    my ($self) = assertNumArgs(1, @_);
#    $log->info($self->{message});
#  }
#
# @description
#
# C<Permabit::AsyncTask> allows you to run perl code in the background and then
# get return values/objects back as well as exceptions.  The module assumes
# that return value is a scalar and it can be any sort of compound object that
# Data::Dumper can serialize.
#
# The kill method can be called to stop the perl code running.  The
# taskTeardown method will always be called, and the subclass should override
# the taskTeardown method to do any necessary cleanup.
#
# $Id$
##
package Permabit::AsyncTask;

use strict;
use warnings FATAL => qw(all);
use Carp;
use Data::Dumper;
use English qw(-no_match_vars);
use Log::Log4perl;
use POSIX qw(WIFSIGNALED WTERMSIG);
use Proc::Simple;
use Time::HiRes qw(sleep time);

use Permabit::Assertions qw(
  assertEq
  assertEqualNumeric
  assertNe
  assertNotDefined
  assertNumArgs
  assertType
);
use Permabit::Exception qw(Signal);
use Permabit::Tempfile;
use Permabit::Utils qw(getRandomSeed);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my $inTeardown = 0;

###############################################################################
# Instantiate a new Permabit::AsyncTask.
##
sub new {
  my ($invocant) = assertNumArgs(1, @_);
  my $class = ref($invocant) || $invocant;
  my $self = bless({
                    parentPid => $PID,
                    _machines => [],
                    _proc     => undef,
                    _status   => "initialized",
                    _tempfile => undef,
                   }, $class);
  return $self;
}

###############################################################################
# Run the AsyncTask.  Normally this method will be overridden in the subclass.
##
sub taskCode {
  my ($self) = assertNumArgs(1, @_);
  assertEqualNumeric($PID, $self->{_childPid});
}

###############################################################################
# Teardown the AsyncTask.
##
sub taskTeardown {
  my ($self) = assertNumArgs(1, @_);
  assertEqualNumeric($PID, $self->{_childPid});
  map { $_->close() } @{$self->{_machines}};
}

###############################################################################
# Record a remote machine being used by the subroutine, so that taskTeardown
# can close the RemoteMachine.
#
# @param machine  the remote machine.
##
sub useMachine {
  my ($self, $machine) = assertNumArgs(2, @_);
  assertEqualNumeric($PID, $self->{parentPid});
  assertType("Permabit::RemoteMachine", $machine);
  push(@{$self->{_machines}}, $machine);
}

###############################################################################
# Query whether the subroutine has not been started.
#
# @return true if the subroutine has not been started
##
sub isNotStarted {
  my ($self) = assertNumArgs(1, @_);
  assertEqualNumeric($PID, $self->{parentPid});
  return $self->{_status} eq "initialized";
}

###############################################################################
# Query whether the subroutine is running.
#
# @return true if the subroutine is running
##
sub isRunning {
  my ($self) = assertNumArgs(1, @_);
  assertEqualNumeric($PID, $self->{parentPid});
  $self->_poll();
  return $self->{_status} eq "pending";
}

###############################################################################
# Kill this subroutine.
##
sub kill {
  my ($self) = assertNumArgs(1, @_);
  assertEqualNumeric($PID, $self->{parentPid});
  $self->_poll();
  if ($self->{_proc}) {
    $self->{_proc}->kill("SIGUSR2");
    $self->{_killCount} //= 12;
    $self->{_killTimer} = time() + 5;
  }
}

###############################################################################
# Wait for the subroutine to finish and return the result
#
# @return the return value of the subroutine
#
# @croaks if the asynchronous subroutine could not be run, or if it ran and
#         threw an exception.
##
sub result {
  my ($self) = assertNumArgs(1, @_);
  assertEqualNumeric($PID, $self->{parentPid});
  $self->_wait();
  if ($self->{_status} eq "ok" || $self->{_status} eq "signal") {
    return $self->{_result};
  }
  croak($self->{_error});
}

###############################################################################
# Start running this asynchronous subroutine.
#
# @return self
##
sub start {
  my ($self) = assertNumArgs(1, @_);
  assertEqualNumeric($PID, $self->{parentPid});
  assertEq("initialized", $self->{_status});
  assertNotDefined($self->{_proc});
  assertNotDefined($self->{_tempfile});

  $self->{_tempfile} = new Permabit::Tempfile(SUFFIX => '.async', UNLINK => 1);
  my $wrapperSub = sub { $self->_runner(); };
  $self->{_proc} = Proc::Simple->new();
  if ($self->{_proc}->start($wrapperSub)) {
    $self->{_status} = "pending";
  } else {
    $log->debug("Proc::Simple::start failed: $OS_ERROR");
    $self->{_status} = "failure";
    $self->{_error}  = "FAILED to start asynchronous subroutine";
    $self->{_proc}   = undef;
  }

  return $self;
}

###############################################################################
# Process the results of the asynchronous subroutine in the child process, if
# it has just finished.
##
sub _poll {
  my ($self) = assertNumArgs(1, @_);
  assertEqualNumeric($PID, $self->{parentPid});
  if ($self->{_proc}) {
    if (!$self->{_proc}->poll()) {
      my $exitStatus = $self->{_proc}->exit_status();
      my $procInfo = ("proc exit status: $exitStatus, file: "
                      . $self->{_tempfile}->filename()
                      . ", pid: " . $self->{_proc}->pid());
      if (WIFSIGNALED($exitStatus)) {
        my $sig = WTERMSIG($exitStatus);
        $self->{_status} = "failure";
        $self->{_error}  = "exit on signal " . $sig;
        $log->debug("caught unexpected signal $sig");
      } else {
        our ($result, $error, $checkBit) = (undef, undef, undef);
        eval { do($self->{_tempfile}->filename()); };
        if ($EVAL_ERROR) {
          $self->{_status} = "failure";
          $self->{_error} = $EVAL_ERROR;
          $log->debug("EVAL_ERROR: $self->{_error}; $procInfo");
        } elsif (!$checkBit) {
          $self->{_status} = "failure";
          $self->{_error} = "internal asyncsub error: bad data dump";
          $log->debug("$self->{_error}; $procInfo");
        } elsif ($error) {
          $self->{_status} = "error";
          $self->{_error} = $error;
          $log->debug("ERROR: $self->{_error}; $procInfo");
        } else {
          $self->{_status} = "ok";
          $self->{_result} = $result;
        }
      }
      $self->{_tempfile} = undef;
      $self->{_proc}     = undef;
      return 0;
    }
    if (defined($self->{_killCount}) && ($self->{_killTimer} < time())) {
      if ($self->{_killCount} > 0) {
        $self->{_proc}->kill("SIGUSR2");
        $self->{_killCount}--;
        $self->{_killTimer} = time() + 5;
      } else {
        $self->{_proc}->kill("SIGKILL");
      }
    }
  }
  return 1;
}

###############################################################################
# Run the asynchronous subroutine in the child process.
##
sub _runner {
  my ($self) = assertNumArgs(1, @_);
  $SIG{USR2} = \&_sigusr2;
  $self->{_childPid} = $PID;
  srand(getRandomSeed());

  my $file = $self->{_tempfile}->filename();
  $self->{_tempfile}->unlink_on_destroy(0);

  my $result = eval { return $self->taskCode(); };
  my $error = $EVAL_ERROR;
  $inTeardown = 1;
  eval { $self->taskTeardown(); };
  if ($EVAL_ERROR) {
    $log->warn("ASYNCTASK CLEANUP FAILURE $PID $EVAL_ERROR");
  }
  my $data = Data::Dumper->Dump([ $result, $error, 1 ],
                                [ qw( result error checkBit )]);
  open FH, ">$file" || POSIX::_exit(2);
  print FH $data, "\n";
  close FH || POSIX::_exit(2);
  POSIX::_exit($error ? 1 : 0);
}

###############################################################################
# Handle a SIGUSR2 in the child process.
##
sub _sigusr2 {
  if (!$inTeardown) {
    die(Permabit::Exception::Signal->new("AsyncTask received a SIGUSR2"));
  }
}

###############################################################################
# Wait for subroutine to finish.
##
sub _wait {
  my ($self) = assertNumArgs(1, @_);
  assertEqualNumeric($PID, $self->{parentPid});
  assertNe("initialized", $self->{_status});
  $self->_poll();
  while ($self->{_status} eq "pending") {
    sleep(0.1);
    $self->_poll();
  }
}

1;
