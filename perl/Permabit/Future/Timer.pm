##
# A subclass of Permabit::Future that repeats an action at a fixed
# time interval (i.e. this is a repeating "timer").
#
# @synopsis
#
#   # Run A every 10 minutes
#   use Permabit::Future::Timer;
#   my $future = Permabit::Future::Timer->new(code         => sub { A(); },
#                                             timeInterval => 10 * $MINUTE);
#   while (1) {
#     $future->poll();
#     # program does other stuff
#   }
#
# $Id$
##
package Permabit::Future::Timer;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Permabit::Assertions qw(
  assertDefined
  assertMinArgs
  assertNumArgs
  assertTrue
);
use Time::HiRes qw(time);

use base qw(Permabit::Future);

#############################################################################
# Creates a Permabit::Future::Timer, which is a type of
# Permabit::Future that runs a piece of code repeatedly at a specified
# time interval.  Takes arguments as key-value pairs.
#
# @param  code          Code to run when the time interval has elapsed.
# @param  timeInterval  Number of seconds to pass between calls to Code.
# @oparam timeFirst     Number of seconds to pass before the first call
#                       to Code (defaults to timeInterval).
#
# @return a new C<Permabit::Future::Timer>
##
sub new {
  my ($invocant, %params) = assertMinArgs(5, @_);
  my $code  = $params{code};
  my $first = $params{timeFirst};
  my $time  = $params{timeInterval};
  assertDefined($code);
  assertTrue(ref($code) eq 'CODE');
  assertDefined($time);
  assertTrue($time);
  my $deadline = time() + (defined($first) ? $first : $time);
  # Convert the specified code and time parameters into the
  # onTimeLimit and timeLimit parameters.  Set the initial deadline.
  return Permabit::Future::new($invocant,
                               onTimeLimit    => $code,
                               timeLimit      => $time,
                               whatFor        => "$time second timer",
                               _deadline      => $deadline,);
}

#############################################################################
# @inherit
##
sub poll {
  my ($self) = assertNumArgs(1, @_);
  if ($self->isDone()) {
    return;  # We were cancelled.
  }
  # Inside poll we may be calling user supplied code, and that code
  # may poll this future.  Use the _nowPolling flag to break the
  # potentially infinite loop.
  if ($self->{_nowPolling}) {
    return;  # We are in a recursively nested call to poll.
  }
  local $self->{_nowPolling} = 1;

  if (time() < $self->{_deadline}) {
    return;  # We haven't hit the time limit.
  }
  # We hit the time limit
  {
    local $_;
    $self->{onTimeLimit}();
  }
  # Set the timer to repeat
  $self->{_deadline} = time() + $self->{timeLimit};
}

1;
