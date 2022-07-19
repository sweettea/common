##
# Test the Permabit::Future module
#
# $Id$
#
# TODO: test newAfterJavaThread.  It's a hassle to test JavaThreads.
##
package testcases::Future_t1;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess croak);
use English qw(-no_match_vars);

use Permabit::Assertions qw(
  assertEqualNumeric
  assertEvalErrorMatches
  assertFalse
  assertMinArgs
  assertNumArgs
  assertTrue
);
use Permabit::Constants;
use Permabit::Future;
use Permabit::Future::AfterAsyncSub;
use Permabit::Future::AfterFuture;
use Permabit::Future::AnyOrder;
use Permabit::Future::InOrder;
use Permabit::Future::List;
use Permabit::Future::Timer;
use Permabit::Utils qw(reallySleep timeToText);
use Time::HiRes qw(time);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

# short timeout
my $SHORT_TIMEOUT = 0.005;
# short nap (slightly longer than $SHORT_TIMEOUT)
my $SHORT_SLEEP   = 1;
# long timeout
my $LONG_TIMEOUT = $HOUR;

my $ASSERTDEFINED_ASSERTION = qr/^assertDefined failed/;
my $NEW_TIMER_ASSERTION
  = qr/^Incorrect number of args to Permabit::Future::Timer::new/;

###############################################################################
# Test that poll/isDone returns the correct value and doesn't croak.
#
# @param   future   The Permabit::Future
# @param   %params  Hash table of the rest of the named parameters
# @param   $params{isDone}        The expected value returned from
#                                 $future->isDone().  Either 0 or 1.
# @oparam  $params{trigger}       $self->{trigger} is set to this before
#                                 the call to $future->poll().
# @oparam  $params{finallyCount}  1 if we expect the finallyCode to run.
# @oparam  $params{timerCount}    1 if we expect the onTimeLimit to run.
##
sub _pollIsDone {
  my ($self, $future, %params) = assertMinArgs(4, @_);
  $self->{finallyCount} = 0;
  $self->{timerCount} = 0;
  if (defined($params{trigger})) {
    $self->{trigger} = $params{trigger};
  }
  eval { $future->poll(); };
  my $error = $EVAL_ERROR;
  assertFalse($error, "poll threw $error");
  assertEqualNumeric($params{isDone}, $future->isDone() ? 1 : 0);
  assertEqualNumeric($params{finallyCount} || 0, $self->{finallyCount});
  assertEqualNumeric($params{timerCount} || 0, $self->{timerCount});
}

###############################################################################
# Test that poll does croak.
#
# @param  future   The Permabit::Future
# @param  %params  Hash table of the rest of the named parameters
# @param  $params{trigger}  $self->{trigger} is set to this before
#                           the call to $future->poll().
# @param  $params{re}       A regular expression to match the thrown error.
##
sub _pollError {
  my ($self, $future, %params) = assertNumArgs(6, @_);
  $self->{trigger} = $params{trigger};
  eval { $future->poll(); };
  assertEvalErrorMatches(qr/$params{re}/, "poll");
}

###############################################################################
# Test a case of Permabit::Future::AfterAsyncSub.
#
# @param   %params  Hash table containing the named parameters
# @param   $params{name}          Name of this test case (for error message)
# @param   $params{code}          Reference to perl code to run asynchrously.
# @param   $params{params}        Reference to parameters to pass to
#                                 Permabit::Future::AfterAsyncSub->new().
# @oparam  $params{errorCount}    1 if we expect the onError to run.
# @oparam  $params{finallyCount}  1 if we expect the finallyCode to run.
# @oparam  $params{successCount}  1 if we expect the onSuccess to run.
# @oparam  $params{timerCount}    1 if we expect the onTimeLimit to run.
##
sub _runAsyncSub {
  my ($self, %params) = assertMinArgs(7, @_);
  my @counts = qw(errorCount finallyCount successCount timerCount);
  my $thread = Permabit::AsyncSub->new(code => $params{code},
                                       killOnDestroy => 1);
  my $future = Permabit::Future::AfterAsyncSub->new(asyncSub => $thread,
                                                    whatFor  => $params{name},
                                                    @{$params{params}});
  {
    local $SIG{TERM} = 'DEFAULT';
    $thread->start();
  }
  map { $self->{$_} = 0; } @counts;
  my $startingAt = time();
  while (!$future->isDone()) {
    if ((time() - $startingAt) > $MINUTE) {
      confess("$params{name} test failure");
    }
    map { assertEqualNumeric(0, $self->{$_},
                             "Problem with $_ value"
                             . " in middle of $params{name} test");
        } @counts;
    $future->poll();
  }
  map { assertEqualNumeric($params{$_} || 0, $self->{$_},
                           "Problem with $_"
                           . " value at end of $params{name} test");
      } @counts;
}


###############################################################################
# Test a case of Future::AfterAsyncSub that croaks
#
# @param   %params  Hash table containing the named parameters below, plus all
#                   the possible named parameters for $self->_runAsyncSub()
# @param  $params{evalError}  If we expect the $future->poll() to throw an
#                             error, a regular expression it must match.
##
sub _runAsyncSubError {
  my ($self, %params) = assertMinArgs(9, @_);
  eval { $self->_runAsyncSub(%params); };
  assertEvalErrorMatches(qr/$params{evalError}/, "In $params{name} test");
}

###############################################################################
# Test the general Future object created by new
##
sub testNew {
  my ($self) = assertNumArgs(1, @_);

  # Codes that bump counters, so that we can determine whether
  # routines are triggered or not
  my $finallySub = sub { ++$self->{finallyCount}; };
  my $timerSub   = sub { ++$self->{timerCount}; };

  # Codes that return predictable values
  my ($whatFor);
  my $triggerSub = sub { return $self->{trigger}; };
  my $whatForSub = sub { return $whatFor; };

  # Test with a trigger, but no codes - now should work
  my $future = Permabit::Future->new(testTrigger => $triggerSub);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  $self->_pollIsDone($future, trigger => 1, isDone => 1);
  $self->_pollIsDone($future, trigger => 0, isDone => 1);
  $self->_pollIsDone($future, trigger => 1, isDone => 1);

  # Test with trigger and codes
  $future = Permabit::Future->new(finallyCode => $finallySub,
                                  onTimeLimit => $timerSub,
                                  testTrigger => $triggerSub);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  $self->_pollIsDone($future, trigger => 1, isDone => 1, finallyCount => 1);
  $self->_pollIsDone($future, trigger => 1, isDone => 1);

  # Test with default time limit action - hitting time
  $future = Permabit::Future->new(finallyCode => $finallySub,
                                  testTrigger => $triggerSub,
                                  timeLimit   => $SHORT_TIMEOUT,
                                  whatFor     => "Test$SHORT_TIMEOUT");
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  reallySleep($SHORT_SLEEP);
  $self->_pollError($future,
                    trigger => 0,
                    re => "^Test$SHORT_TIMEOUT timed out after "
                    . timeToText($SHORT_TIMEOUT));

  # Same test with a whatFor as code
  $whatFor = "WhatFor$SHORT_TIMEOUT";
  $future = Permabit::Future->new(finallyCode => $finallySub,
                                  testTrigger => $triggerSub,
                                  timeLimit   => $SHORT_TIMEOUT,
                                  whatFor     => $whatForSub);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  reallySleep($SHORT_SLEEP);
  $self->_pollError($future,
                    trigger => 0,
                    re => "^$whatFor timed out after "
                          . timeToText($SHORT_TIMEOUT));

  # Test with all codes - don't hit timeout
  $future = Permabit::Future->new(finallyCode => $finallySub,
                                  onTimeLimit => $timerSub,
                                  testTrigger => $triggerSub,
                                  timeLimit   => $LONG_TIMEOUT);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  $self->_pollIsDone($future, trigger => 1, isDone => 1, finallyCount => 1);
  $self->_pollIsDone($future, trigger => 1, isDone => 1);

  # Test with all codes - Hit timeout
  $future = Permabit::Future->new(finallyCode => $finallySub,
                                  onTimeLimit => $timerSub,
                                  testTrigger => $triggerSub,
                                  timeLimit   => $SHORT_TIMEOUT);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  reallySleep($SHORT_SLEEP);
  $self->_pollIsDone($future, trigger => 0, isDone => 1, finallyCount => 1,
                     timerCount => 1);
  $self->_pollIsDone($future, trigger => 0, isDone => 1);
  $self->_pollIsDone($future, trigger => 1, isDone => 1);

  # Test with all codes - Hit trigger and timeout
  $future = Permabit::Future->new(finallyCode => $finallySub,
                                  onTimeLimit => $timerSub,
                                  testTrigger => $triggerSub,
                                  timeLimit   => $SHORT_TIMEOUT);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  reallySleep($SHORT_SLEEP);
  $self->_pollIsDone($future, trigger => 1, isDone => 1, finallyCount => 1);
  $self->_pollIsDone($future, trigger => 1, isDone => 1);
  $self->_pollIsDone($future, trigger => 0, isDone => 1);

  # Test addTime
  $future = Permabit::Future->new(finallyCode => $finallySub,
                                  onTimeLimit => $timerSub,
                                  testTrigger => $triggerSub,
                                  timeLimit   => $SHORT_TIMEOUT);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  $future->addTime($LONG_TIMEOUT);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  reallySleep($SHORT_SLEEP);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  $future->addTime(-$LONG_TIMEOUT);
  $self->_pollIsDone($future, trigger => 0, isDone => 1, finallyCount => 1,
                     timerCount => 1);
}

###############################################################################
# Test $_ interactions between a Future::List and a Future object
##
sub testArg {
  my ($self) = assertNumArgs(1, @_);

  # Always trigger
  my $triggerSub = sub { return 1; };

  # Use $_ in a <> operation
  my $angleSub = sub {
    open(my $H, "ls / |") || croak("Failed to run ls");
    while (<$H>) {
      $log->debug($_);
    }
  };
  my $angleFuture = Permabit::Future->new(finallyCode => $angleSub,
                                          testTrigger => $triggerSub,
                                          timeLimit   => $SHORT_TIMEOUT);

  # Use $_ in a map operation
  my $mapSub = sub {
    map { $log->debug($_); } qw(fee fie foe foo);
  };
  my $mapFuture = Permabit::Future->new(finallyCode => $mapSub,
                                        testTrigger => $triggerSub,
                                        timeLimit   => $SHORT_TIMEOUT);

  my $futureList = Permabit::Future::List->new($angleFuture, $mapFuture);
  $futureList->poll();
  assertTrue($futureList->count() == 0, "futureList should be empty");
}

###############################################################################
# Test the Future::AfterAsyncSub object
##
sub testAsyncSub {
  my ($self) = assertNumArgs(1, @_);

  # Codes that bump counters, so that we can determine whether
  # routines are triggered or not
  my @subs = (finallyCode => sub { ++$self->{finallyCount}; },
              onError     => sub { ++$self->{errorCount}; },
              onSuccess   => sub { ++$self->{successCount}; },
              onTimeLimit => sub { ++$self->{timerCount}; });
  my @subsNoFinally = @subs[2..7];
  my @subsNoError   = @subs[0..1, 4..7];
  my @subsNoSuccess = @subs[0..3, 6..7];
  my @subsNoTimer   = @subs[0..5];

  # Codes to run using AsyncSub
  my $asyncError   = sub { die('foo'); };
  my $asyncSuccess = sub { return 1; };
  my $asyncTimeout = sub { reallySleep($HOUR); };

  # Test an underspecified object - should not work
  eval { Permabit::Future::AfterAsyncSub->new(); };
  assertEvalErrorMatches($ASSERTDEFINED_ASSERTION,
                         "Permabit::Future::AfterAsyncSub->new()"
                         . " threw $EVAL_ERROR");

  # Test a successful object
  $self->_runAsyncSub(name   => "Successful AsyncSub",
                      code   => $asyncSuccess,
                      params => [@subs, timeLimit => $LONG_TIMEOUT],
                      finallyCount => 1,
                      successCount => 1 );

  # Test an error object
  $self->_runAsyncSub(name   => "Failing AsyncSub",
                      code   => $asyncError,
                      params => [@subs, timeLimit => $LONG_TIMEOUT],
                      errorCount => 1,
                      finallyCount => 1 );

  # Test a timed out object
  $self->_runAsyncSub(name   => "Timed Out AsyncSub",
                      code   => $asyncTimeout,
                      params => [@subs, timeLimit => $SHORT_TIMEOUT],
                      finallyCount => 1,
                      timerCount => 1 );

  # Test a successful object without an onSuccess
  $self->_runAsyncSub(name   => "Successful AsyncSub Without Success",
                      code   => $asyncSuccess,
                      params => [@subsNoSuccess, timeLimit => $LONG_TIMEOUT],
                      finallyCount => 1 );

  # Test an error object without an onError
  my $name = "Failing AsyncSub Without Error";
  $self->_runAsyncSubError(name      => $name,
                           code      => $asyncError,
                           params    => [@subsNoError,
                                         timeLimit => $LONG_TIMEOUT],
                           evalError => "^Error while waiting for $name: "
                                        . "foo at");

  # Test a timed out object without an onTimeLimit
  $name = "Timed Out AsyncSub Without Timer";
  $self->_runAsyncSubError(name      => $name,
                           code      => $asyncTimeout,
                           params    => [@subsNoTimer,
                                         timeLimit => $SHORT_TIMEOUT],
                           evalError => "^$name timed out after ");

  # Test a successful object without a finallyCode
  $self->_runAsyncSub(name   => "Successful AsyncSub Without Finally",
                      code   => $asyncSuccess,
                      params => [@subsNoFinally, timeLimit => $LONG_TIMEOUT],
          successCount => 1 );

  # Test an error object without a finallyCode
  $self->_runAsyncSub(name   => "Failing AsyncSub Without Finally",
                      code   => $asyncError,
                      params => [@subsNoFinally, timeLimit => $LONG_TIMEOUT],
                      errorCount => 1 );

  # Test a timed out object without a finallyCode
  $self->_runAsyncSub(name   => "Timed Out AsyncSub Without Finally",
                      code   => $asyncTimeout,
                      params => [@subsNoFinally, timeLimit => $SHORT_TIMEOUT],
                      timerCount => 1 );
}

###############################################################################
# Test Futures that are chained onto other Futures.
##
sub testChaining {
  my ($self) = assertNumArgs(1, @_);

  # Codes that bump counters, so that we can determine whether
  # routines are triggered or not
  my ($countP, $count1, $count2);
  my $finallyP = sub { $countP++;};
  my $finally1 = sub { $count1++;};
  my $finally2 = sub { $count2++;};

  # Trigger codes that return predictable values
  my ($trigger1, $trigger2);
  my $trigger1Sub = sub { return $trigger1; };
  my $trigger2Sub = sub { return $trigger2; };

  # Test Future::AfterFuture
  my $future1 = Permabit::Future->new(finallyCode => $finally1,
                                      testTrigger => $trigger1Sub,);
  my $future = Permabit::Future::AfterFuture->new(finallyCode => $finallyP,
                                                  future      => $future1,);
  ($countP, $count1, $trigger1) = (0, 0, 0);
  $future->poll();
  assertEqualNumeric(0, $countP);
  assertEqualNumeric(0, $count1);
  $trigger1 = 1;
  $future->poll();
  assertEqualNumeric(1, $countP);
  assertEqualNumeric(1, $count1);
  $future->poll();
  assertEqualNumeric(1, $countP);
  assertEqualNumeric(1, $count1);

  # Test Future::AnyOrder (none, then 1, then 2)
  $future1 = Permabit::Future->new(finallyCode => $finally1,
                                   testTrigger => $trigger1Sub,);
  my $future2 = Permabit::Future->new(finallyCode => $finally2,
                                      testTrigger => $trigger2Sub,);
  $future = Permabit::Future::AnyOrder->new(finallyCode => $finallyP,
                                            list => [$future1, $future2],);
  ($countP, $count1, $count2, $trigger1, $trigger2) = (0, 0, 0, 0, 0);
  $future->poll();
  assertEqualNumeric(0, $countP);
  assertEqualNumeric(0, $count1);
  assertEqualNumeric(0, $count2);
  ($trigger1, $trigger2) = (1, 0);
  $future->poll();
  assertEqualNumeric(0, $countP);
  assertEqualNumeric(1, $count1);
  assertEqualNumeric(0, $count2);
  ($trigger1, $trigger2) = (0, 1);
  $future->poll();
  assertEqualNumeric(1, $countP);
  assertEqualNumeric(1, $count1);
  assertEqualNumeric(1, $count2);

  # Test Future::AnyOrder (none, then 2, then both)
  $future1 = Permabit::Future->new(finallyCode => $finally1,
                                   testTrigger => $trigger1Sub,);
  $future2 = Permabit::Future->new(finallyCode => $finally2,
                                   testTrigger => $trigger2Sub,);
  $future = Permabit::Future::AnyOrder->new(finallyCode => $finallyP,
                                            list => [$future1, $future2],);
  ($countP, $count1, $count2, $trigger1, $trigger2) = (0, 0, 0, 0, 0);
  $future->poll();
  assertEqualNumeric(0, $countP);
  assertEqualNumeric(0, $count1);
  assertEqualNumeric(0, $count2);
  ($trigger1, $trigger2) = (0, 1);
  $future->poll();
  assertEqualNumeric(0, $countP);
  assertEqualNumeric(0, $count1);
  assertEqualNumeric(1, $count2);
  ($trigger1, $trigger2) = (1, 1);
  $future->poll();
  assertEqualNumeric(1, $countP);
  assertEqualNumeric(1, $count1);
  assertEqualNumeric(1, $count2);

  # Test Future::AnyOrder (both)
  $future1 = Permabit::Future->new(finallyCode => $finally1,
                                   testTrigger => $trigger1Sub,);
  $future2 = Permabit::Future->new(finallyCode => $finally2,
                                   testTrigger => $trigger2Sub,);
  $future = Permabit::Future::AnyOrder->new(finallyCode => $finallyP,
                                            list => [$future1, $future2],);
  ($countP, $count1, $count2, $trigger1, $trigger2) = (0, 0, 0, 0, 0);
  $future->poll();
  assertEqualNumeric(0, $countP);
  assertEqualNumeric(0, $count1);
  assertEqualNumeric(0, $count2);
  ($trigger1, $trigger2) = (1, 1);
  $future->poll();
  assertEqualNumeric(1, $countP);
  assertEqualNumeric(1, $count1);
  assertEqualNumeric(1, $count2);

  # Test Future::InOrder (none, then 1, then 2)
  $future1 = Permabit::Future->new(finallyCode => $finally1,
                                   testTrigger => $trigger1Sub,);
  $future2 = Permabit::Future->new(finallyCode => $finally2,
                                   testTrigger => $trigger2Sub,);
  $future = Permabit::Future::InOrder->new(finallyCode => $finallyP,
                                           list => [$future1, $future2],);
  ($countP, $count1, $count2, $trigger1, $trigger2) = (0, 0, 0, 0, 0);
  $future->poll();
  assertEqualNumeric(0, $countP);
  assertEqualNumeric(0, $count1);
  assertEqualNumeric(0, $count2);
  ($trigger1, $trigger2) = (1, 0);
  $future->poll();
  assertEqualNumeric(0, $countP);
  assertEqualNumeric(1, $count1);
  assertEqualNumeric(0, $count2);
  ($trigger1, $trigger2) = (0, 1);
  $future->poll();
  assertEqualNumeric(1, $countP);
  assertEqualNumeric(1, $count1);
  assertEqualNumeric(1, $count2);

  # Test Future::InOrder (none, then 2, then both)
  $future1 = Permabit::Future->new(finallyCode => $finally1,
                                   testTrigger => $trigger1Sub,);
  $future2 = Permabit::Future->new(finallyCode => $finally2,
                                   testTrigger => $trigger2Sub,);
  $future = Permabit::Future::InOrder->new(finallyCode => $finallyP,
                                           list => [$future1, $future2],);
  ($countP, $count1, $count2, $trigger1, $trigger2) = (0, 0, 0, 0, 0);
  $future->poll();
  assertEqualNumeric(0, $countP);
  assertEqualNumeric(0, $count1);
  assertEqualNumeric(0, $count2);
  ($trigger1, $trigger2) = (0, 1);
  $future->poll();
  assertEqualNumeric(0, $countP);
  assertEqualNumeric(0, $count1);
  assertEqualNumeric(0, $count2);
  ($trigger1, $trigger2) = (1, 1);
  $future->poll();
  assertEqualNumeric(1, $countP);
  assertEqualNumeric(1, $count1);
  assertEqualNumeric(1, $count2);
}

###############################################################################
# Test that a general Future object can safely invoke poll on itself
# from inside its sub arguments.
##
sub testNested {
  my ($self) = assertNumArgs(1, @_);
  my $future;
  my $nested = undef;

  # Codes that make nested calls to poll, so we can detect out of
  # control recursion.
  my $finallySub = sub {
    if (defined($nested)) {
      confess("finallySub nested inside $nested");
    }
    $nested = "finallySub";
    $future->poll();
    $nested = undef;
  };
  my $timerSub = sub {
    if (defined($nested)) {
      confess("timerSub nested inside $nested");
    }
    $nested = "timerSub";
    $future->poll();
    $nested = undef;
  };

  # And codes that also return predictable values
  my $triggerSub = sub {
    if (defined($nested)) {
      confess("triggerSub nested inside $nested");
    }
    $nested = "triggerSub";
    $future->poll();
    $nested = undef;
    return $self->{trigger};
  };

  # Test with trigger and codes
  $future = Permabit::Future->new(finallyCode => $finallySub,
                                  onTimeLimit => $timerSub,
                                  testTrigger => $triggerSub);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  $self->_pollIsDone($future, trigger => 1, isDone => 1);
  $self->_pollIsDone($future, trigger => 1, isDone => 1);

  # Test with default time limit action - hitting time
  $future = Permabit::Future->new(finallyCode => $finallySub,
                                  testTrigger => $triggerSub,
                                  timeLimit   => $SHORT_TIMEOUT,
                                  whatFor     => "Test$SHORT_TIMEOUT");
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  reallySleep($SHORT_SLEEP);
  $self->_pollError($future,
                    trigger => 0,
                    re => "^Test$SHORT_TIMEOUT timed out after "
                          . timeToText($SHORT_TIMEOUT));

  # Test with all codes - don't hit timeout
  $future = Permabit::Future->new(finallyCode => $finallySub,
                                  onTimeLimit => $timerSub,
                                  testTrigger => $triggerSub,
                                  timeLimit   => $LONG_TIMEOUT);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  $self->_pollIsDone($future, trigger => 1, isDone => 1);
  $self->_pollIsDone($future, trigger => 1, isDone => 1);

  # Test with all codes - Hit timeout
  $future = Permabit::Future->new(finallyCode => $finallySub,
                                  onTimeLimit => $timerSub,
                                  testTrigger => $triggerSub,
                                  timeLimit   => $SHORT_TIMEOUT);
  $self->_pollIsDone($future, trigger => 0, isDone => 0);
  reallySleep($SHORT_SLEEP);
  $self->_pollIsDone($future, trigger => 0, isDone => 1);
  $self->_pollIsDone($future, trigger => 0, isDone => 1);
  $self->_pollIsDone($future, trigger => 1, isDone => 1);
}

###############################################################################
# Test the Future::Timer object
##
sub testTimer {
  my ($self) = assertNumArgs(1, @_);

  # Codes that bump counters, so that we can determine whether
  # routines are triggered or not
  my $timerCount = 0;
  my $timerSub   = sub { ++$timerCount; };

  # Test an underspecified timer - should not work
  eval { Permabit::Future::Timer->new(); };
  assertEvalErrorMatches($NEW_TIMER_ASSERTION,
                         'Permabit::Future::Timer->new() threw '
                         . $EVAL_ERROR);
  eval { Permabit::Future::Timer->new(code => $timerSub); };
  assertEvalErrorMatches($NEW_TIMER_ASSERTION,
                         'Permabit::Future::Timer->new() threw '
                         . $EVAL_ERROR);
  eval { Permabit::Future::Timer->new(timeInterval => 1) };
  assertEvalErrorMatches($NEW_TIMER_ASSERTION,
                         'Permabit::Future::Timer->new() threw '
                         . $EVAL_ERROR);

  # now a real timer
  my $timer = Permabit::Future::Timer->new(code => $timerSub,
                                           timeInterval => 0.5);
  my $t = time();
  while ($timerCount < 5) {
    my $oldCount = $timerCount;
    $self->_pollIsDone($timer, isDone => 0);
    if ($timerCount == $oldCount) {
      if (($t - time()) > $MINUTE) {
        croak('timer did not go off');
      }
    } elsif ($timerCount == ($oldCount + 1)) {
      $t = time();
    } else {
      croak('timerCount is whacked');
    }
  }
}

###############################################################################
# Test the Future::List object, and test the Future::Timer objects
# when using the timeFirst option.
##
sub testTimerFirst {
  my ($self) = assertNumArgs(1, @_);

  # Codes that bump counters, so that we can determine when routines
  # are triggered
  my ($firstCount, $regularCount) = (0, 0);
  my $firstSub   = sub {
    ++$firstCount;
    $log->info("First Timer number $firstCount");
  };
  my $regularSub = sub {
    ++$regularCount;
    $log->info("Regular Timer number $regularCount");
  };
  $log->info("Starting Timers");

  # Set up a pair of timers that will go off alternately at 1.5 second
  # intervals.  A long delay in thread scheduling can cause this test
  # to fail.  It originally used a half-second interval and five
  # iterations.  The longer time (1.5s) and fewer iterations (2) is an
  # attempt to make this fail less frequently.
  my @timers = (Permabit::Future::Timer->new(code => $firstSub,
                                             timeFirst => 1.5,
                                             timeInterval => 3),
                Permabit::Future::Timer->new(code => $regularSub,
                                             timeInterval => 3));
  my $futureList = Permabit::Future::List->new(@timers);

  my $t = time();
  while ($regularCount < 2) {
    my $oldCount = $firstCount + $regularCount;
    $futureList->poll();
    my $newCount = $firstCount + $regularCount;
    if ($newCount < $oldCount) {
      croak("Time going backwards, with oldCount = $oldCount, "
            . "firstCount = $firstCount and regularCount = $regularCount");
    }
    if ($newCount == $oldCount) {
      if (($t - time()) > $MINUTE) {
        croak("A timer did not go off, with firstCount = $firstCount"
              . " and regularCount = $regularCount");
      }
      next;
    }
    if ($newCount > ($oldCount + 2)) {
      croak("Too many timers went off, with oldCount = $oldCount, "
            . "firstCount = $firstCount and regularCount = $regularCount");
    }
    if ($newCount == ($oldCount + 2)) {
      $log->warn("Two timers went off, with oldCount = $oldCount, "
                 . "firstCount = $firstCount and "
                 . "regularCount = $regularCount");
    }
    if (($firstCount != $regularCount)
        && (($firstCount - $regularCount) != 1)) {
      croak("Timers went off in the wrong order, with firstCount = $firstCount"
            . " and regularCount = $regularCount");
    }
  }
}

1;
