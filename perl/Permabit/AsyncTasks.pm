##
# Perl object that contains a list of asynchronous tasks, where each task
# is wrapped in a Permabit::AsyncTask.
#
# @synopsis
#
#   # In Permabit::Testcase, we define:
#   sub getAsyncTasks {
#     my ($self) = assertNumArgs(1, @_);
#     $self->{_asyncTasks} //= Permabit::AsyncTasks->new();
#     return $self->{_asyncTasks};
#   }
#
#   # and in subclasses of Testcase, we do code like:
#   use Permabit::VDOTask::SleepAndStopDory;
#   my $stopTask = Permabit::VDOTask::SleepAndStopDory->new($delay, $device);
#   $self->getAsyncTasks()->addTask($stopTask);
#   $stopTask->start();
#
#   # and in the Testcase::run_coda method, we do this to check for errors:
#   my $notStarted = $self->getAsyncTasks()->countNotStarted();
#   if ($notStarted > 0) {
#     confess("$notStarted AsyncTasks were never started");
#   }
#   my $running = $self->getAsyncTasks()->countRunning();
#   if ($running > 0) {
#     confess("$running AsyncTasks are still running");
#   }
#
#   # and in the Testcase::tear_down method, we do this to stop the AsyncTask
#   # processing if a test is killed by a timeout:
#   $self->getAsyncTasks()->kill();
#
# $Id$
##
package Permabit::AsyncTasks;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Log::Log4perl;
use Permabit::Assertions qw(assertMinArgs assertNumArgs assertType);
use Permabit::Utils qw(retryUntilTimeout);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

############################################################################
# Creates a C<Permabit::AsyncTasks>.
#
# @param tasks  Initial list of C<Permabit::AsyncTask>s
#
# @return a new C<Permabit::AsyncTasks>
##
sub new {
  my $invocant = shift;
  my $class = ref($invocant) || $invocant;
  my $self = bless [@_], $class;
  map { assertType("Permabit::AsyncTask", $_) } @$self;
  return $self;
}

############################################################################
# Add a C<Permabit::AsyncTask> to the list of tasks
#
# @param task  A C<Permabit::AsyncTask>
##
sub addTask {
  my ($self, $task) = assertNumArgs(2, @_);
  assertType("Permabit::AsyncTask", $task);
  push(@$self, $task);
}

############################################################################
# Add a list of C<Permabit::AsyncTask>s to the list of tasks
#
# @param tasks  Some C<Permabit::AsyncTask>s
##
sub addTasks {
  my ($self, @tasks) = assertMinArgs(2, @_);
  map { $self->addTask($_) } @tasks;
}

############################################################################
# Count the number of tasks that have not been started.
#
# @return the number of tasks that have not been started.
##
sub countNotStarted {
  my ($self) = assertNumArgs(1, @_);
  return scalar(grep { $_->isNotStarted() } @$self);
}

############################################################################
# Count the number of tasks that are still running
#
# @return the number of tasks that are still running
##
sub countRunning {
  my ($self) = assertNumArgs(1, @_);
  return scalar(grep { $_->isRunning() } @$self);
}

############################################################################
# Finish all tasks.  Start any task that has not been started.
#
# @croaks if any task croaks
##
sub finish {
  my ($self) = assertNumArgs(1, @_);
  $self->start();
  map { $_->result() } @$self;
}

############################################################################
# Kill all tasks.
##
sub kill {
  my ($self) = assertNumArgs(1, @_);
  if ($self->countRunning() > 0) {
    map { $_->kill() } @$self;
    retryUntilTimeout(sub { return $self->countRunning() == 0; },
                      "Cannot kill all running tasks", 30);
  }
}

############################################################################
# Start all tasks.  Skip any task that was already started.
##
sub start {
  my ($self) = assertNumArgs(1, @_);
  map { $_->start() } grep { $_->isNotStarted() } @$self;
}

1;
