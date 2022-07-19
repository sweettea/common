##
# Perl objects that represent future actions.
#
# A future action is code that must be run in the future, after a
# triggering condition occurs. The trigger condition can be based upon
# time, or upon the result of any code that evaluates the environment.
#
# The basic case is to use code to evaluate something in the
# environment. The code that does this is supplied by the caller.
#
# Other cases are implemented in subclasses of Future:
#
#   Permabit::Future::AfterAsyncSub waits for an AsyncSub to complete.
#
#   Permabit::Future::AfterFuture waits for a single embedded Future
#   to finish.
#
#   Permabit::Future::AnyOrder waits for a list of Futures to finish
#   in any order.
#
#   Permabit::Future::InOrder waits for a list of Futures to finish
#   in a specific order.
#
#   Permabit::Future::List manages a arbitrary and changable list of
#   Permabit::Future objects.
#
#   Permabit::Future::Timer runs an action repeatedly at a specified
#   time interval.
#
# All official members of C<Permabit::Future> objects are in bumpy
# case or begin with an underscore.  The user of C<Permabit::Future>
# can decorate a C<Permabit::Future> object with any additional
# members that are named with only lowercase characters.
#
# @synopsis
#
#   # Run A asynchronously, then run B asynchronously.
#   use Permabit::AsyncSub;
#   use Permabit::Future::AfterAsyncSub;
#   use Permabit::Future::InOrder;
#   my $aThread = Permabit::AsyncSub->new(code => sub { A(); });
#   my $bThread = Permabit::AsyncSub->new(code => sub { B(); });
#   my $aFuture = Permabit::Future::AfterAsyncSub
#     ->new(asyncSub    => aThread,
#           finallyCode => sub { $bThread->start(); },
#           timeLimit   => 30 * $MINUTE,
#           whatFor     => 'A');
#   my $bFuture
#     = Permabit::Future::AfterAsyncSub->new(asyncSub    => bThread,
#                                            timeLimit   => 30 * $MINUTE,
#                                            whatFor     => 'B');
#   my $future = Permabit::Future::InOrder->new(list => [$aFuture, $bFuture]);
#   $aThread->start();
#   while (!$future->isDone()) {
#     # program does other stuff
#     $future->poll();
#   }
#
#
#   # Run A and B asynchronously, then run C synchronously.
#   use Permabit::AsyncSub;
#   use Permabit::Future::AfterAsyncSub;
#   use Permabit::Future::AnyOrder;
#   my $aThread = Permabit::AsyncSub->new(code => sub { A(); });
#   my $bThread = Permabit::AsyncSub->new(code => sub { B(); });
#   my $aFuture
#     = Permabit::Future::AfterAsyncSub->new(asyncSub  => aThread,
#                                            timeLimit => 30 * $MINUTE,
#                                            whatFor   => 'A');
#   my $bFuture
#     = Permabit::Future::AfterAsyncSub->new(asyncSub  => bThread,
#                                            timeLimit => 30 * $MINUTE,
#                                            whatFor   => 'B');
#   my $future = Permabit::Future::AnyOrder->new(finallyCode => sub { C(); },
#                                                list => [$aFuture, $bFuture]);
#   $aThread->start();
#   $bThread->start();
#   while (!$future->isDone()) {
#     # program does other stuff
#     $future->poll();
#   }
#
# $Id$
##
package Permabit::Future;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Carp qw(confess);
use Permabit::Assertions qw(assertMinMaxArgs assertNumArgs assertTrue);
use Permabit::Utils qw(timeToText);
use Storable qw(dclone);
use Time::HiRes qw(time);

#****************************************************************************
# Caveat Programmer!
#
#  In practice, using Permabit::Future we have seen some odd
#  properties of perl.  So, it is a very good idea to follow these
#  rules in this module.
#
#  We see these problems because there are many places in the
#  Permabit::Future interfaces where the caller passes in some code,
#  that is executed by Permabit::Future code as part of another call.
#  There are potential interactions between the caller of this code,
#  this code, and code supplied by the user that we call.
#
#  The first problem concerns the use of $_ as the implicit iteration
#  control variable.  Special care must be taken with grep and map,
#  which always use $_.  $_ is a global variable, and using it for an
#  iteration inside an iteration is asking for trouble.
#
#  RULE ONE: In this module, only use a $_ constructs when absolutely
#  sure that the code will not invoke a user supplied sub.
#
#  The second problem concerns the recursive use of Permabit::Future
#  objects.  Always assume that any call out to user supplied code can
#  invoke any Permabit::Future interface to manipulate the same
#  Permabit::Future object that we are using.
#
#  RULE TWO: In this module, never invoke a user supplied sub while
#  iterating directly over a list.  Always copy the list, and iterate
#  over the copy.
#
#  The third problem also concerns the use of $_ as the implicit
#  iteration control variable.  Sometimes the callers of a
#  Permabit::Future method are using $_, and user supplied code to a
#  Permabit::Future method are also using $_.  In particular, we have
#  seen bad behavior in PBFSVerifier (it uses while <$ENUM>), and have
#  seen suspicious behaviour in JavaPM.
#
#  RULE THREE:  When calling user supplied code, localize $_.
#
#****************************************************************************

#############################################################################
# @paramList{new}
my %properties = (
  # @ple Code to execute when the condition happens.
  #      If undefined, no code is executed.
  finallyCode => undef,
  # @ple Code to execute when the time limit has occurred.
  #      If undefined, croak is called.
  onTimeLimit => undef,
  # @ple Code that returns true if the condition we are waiting for
  #      has happened.  Subclasses of Permabit::Future that override
  #      poll() or testTrigger() do not use this value.
  testTrigger => undef,
  # @ple For a simple timeout, the number of seconds to wait for the
  #      condition to happen.  If it takes longer than this, the timeout
  #      triggers.  For a complex timeout, this is a reference to code
  #      that returns true when the time limit has triggered.  If not
  #      specified, the time limit will never trigger.
  timeLimit => undef,
  # @ple Description of what this Future is waiting for. This can be
  #      either a string or code that returns a string.  Subclasses of
  #      Permabit::Future that override getWhatFor() do not use this value.
  whatFor => 'something',
);
##

#############################################################################
# Creates a C<Permabit::Future>. C<new> optionally takes arguments, in
# the form of key-value pairs.
#
# @params{new}
#
# @return a new C<Permabit::Future>
##
sub new {
  my $invocant = shift;
  my $class = ref($invocant) || $invocant;
  my $self = bless { %{ dclone(\%properties) },
                     # Overrides previous values
                     @_,
                     # true if we are done with this future
                     _done => 0,
                     # true if we are currently polling this future
                     _nowPolling => 0,
                   }, $class;
  return $self;
}

#############################################################################
# Extend the timeout deadline(s) by adding a specified number of
# seconds.
#
# @param adjustment  Number of seconds to extend the deadlines.
##
sub addTime {
  my ($self, $adjustment) = assertNumArgs(2, @_);
  if (defined($self->{_deadline})) {
    $self->{_deadline} += $adjustment;
  }
}

#############################################################################
# Cancels a C<Permabit::Future>
##
sub cancel {
  my ($self) = assertNumArgs(1, @_);
  $self->{_done} = 1;
}

#############################################################################
# Get the string describing what this C<Permabit::Future> is waiting
# for.
#
# @return description
##
sub getWhatFor {
  my ($self) = assertNumArgs(1, @_);
  my $whatFor = $self->{whatFor};
  return (ref($whatFor) eq "CODE") ? $whatFor->() : $whatFor;
}

#############################################################################
# Tells if a condition has already triggered and been processed.
#
# @return true if the condition has already triggered.
##
sub isDone {
  my ($self) = assertNumArgs(1, @_);
  return $self->{_done};
}

#############################################################################
# Polls to see if the condition has triggered. If so, calls the
# finallyCode.
#
# @croaks if a timeout occurs
##
sub poll {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{_done}) {
    return;  # We triggered in a prior call, or we were cancelled.
  }
  # Inside poll we may be calling user supplied code, and that code
  # may poll this future.  Use the _nowPolling flag to break the
  # potentially infinite loop.
  if ($self->{_nowPolling}) {
    return;  # We are in a recursively nested call to poll.
  }
  local $self->{_nowPolling} = 1;
  # There are strange interaction between the use of $_ in our callers
  # (in particular, Permabit::Future::List::poll) and the stuff we are
  # going to call.  And we have no control over what we call.  So, we
  # localize $_.  In particular we have seen bad behavior when call
  # the PBFSVerifier (it uses while (<$ENUM>), and have seen
  # suspicious behaviour in JavaPM.
  local $_;
  # Evaluate the trigger.
  if (!$self->testTrigger()) {
    if (!$self->{timeLimit}) {
      return;  # We didn't trigger, and there is no time limit.
    }
    if (ref($self->{timeLimit}) && (ref($self->{timeLimit}) eq "CODE")) {
      if (!$self->{timeLimit}()) {
        return;  # We didn't trigger, and the complex time limit didn't trigger
      }
      if ($self->{_done}) {
        return;  # The time limit code cancelled.
      }
    } else {
      $self->{_deadline} ||= time() + $self->{timeLimit};
      if (time() < $self->{_deadline}) {
        return;  # We didn't trigger, and haven't hit the simple time limit.
      }
    }
    # We hit the time limit without triggering.
    if (defined($self->{onTimeLimit})) {
      $self->{onTimeLimit}();
    } else {
      my $whatFor = $self->getWhatFor();
      confess("$whatFor timed out after " . timeToText($self->{timeLimit}));
    }
  }
  # We triggered or we timed out.
  if (!$self->{_done} && defined($self->{finallyCode})) {
    $self->{finallyCode}();
  }
  $self->{_done} = 1;
}

#############################################################################
# Repeatedly polls the future until it is done.
#
# @oparam  interval  Number of seconds to sleep between polls.  If not
#                    specified, the default is 1 second.
#
# @croaks if called inside a call to poll(), which is guaranteed to be
#         an infinite loop.
##
sub pollUntilDone {
  my ($self, $interval) = assertMinMaxArgs([1], 1, 2, @_);
  if ($self->{_nowPolling}) {
    # We have entered an infinite loop.  This can never be correct.
    confess("pollUntilDone called inside poll, resulting in an infinite loop");
  }
  $self->poll();
  while (!$self->testDonePolling()) {
    sleep($interval);
    $self->poll();
  }
}

#############################################################################
# Tells if the future is done for polling purposes.
#
# @return true if the future is done, or if all embedding futures are done.
#              A subclass can return true even when isDone() would return
#              false.
##
sub testDonePolling {
  my ($self) = assertNumArgs(1, @_);
  return $self->{_done};
}

#############################################################################
# Test to see if the Future's condition has triggered.
#
# @return the value returned from $self->{testTrigger},
#         which is true if the condition has triggered.
##
sub testTrigger {
  my ($self) = assertNumArgs(1, @_);
  return $self->{testTrigger}();
}

1;
