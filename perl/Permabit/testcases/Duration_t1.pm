##
# Test the Duration module
#
# $Id$
##
package testcases::Duration_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Permabit::Assertions qw(
  assertDefined
  assertEvalErrorMatches
  assertNumArgs
);
use Permabit::Constants;
use Permabit::Duration;

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

# Friday, July 5, 2013, 6:15 PM (arbitrary)
my $START_TIME = 1373062500;

my %DURATIONS = (s => 1,
                 m => $MINUTE,
                 h => $HOUR,
                 d => $DAY,
                 w => $DAY * 7,
                );

######################################################################
# Check that a given spec behaves as expected.
#
# @param duration  The expected length of time covered by the spec
# @param spec      The spec to check
##
sub assertDuration {
  my ($self, $duration, $spec) = assertNumArgs(3, @_);
  my $timeSpec = Permabit::Duration->new($spec, $START_TIME);
  $log->info($spec);
  $self->assert_num_equals($duration, $timeSpec->durationSeconds());
  $self->assert_num_equals($duration - 10,
                           $timeSpec->durationSeconds($START_TIME + 10));
  $self->assert_num_equals($START_TIME + $duration, $timeSpec->endTime());
}

######################################################################
# Test Permabit::Duration.
##
sub testDuration {
  my ($self) = assertNumArgs(1, @_);

  # Test durations of the form <number>
  for (my $seconds = 0; $seconds < 3; $seconds++) {
    $self->assertDuration($seconds, $START_TIME + $seconds);
  }

  # Test durations of the form <number><unit>
  foreach my $unit (qw(s m h d w)) {
    $self->assertDuration($DURATIONS{$unit} * 15, "15$unit");
  }

  # Test durations of the form <day name><hour>:<minute>
  my $days = 0;
  foreach my $day (qw(F A S M T W R)) {
    $self->assertDuration(($MINUTE * 15) + ($days * $DAY), "${day}18:30");
    $self->assertDuration($days * $DAY, "${day}18:15");
    $days++;
  }

  $days = 1;
  foreach my $day (qw(A S M T W R F)) {
    $self->assertDuration(($days * $DAY) - ($MINUTE * 15), "${day}18:00");
    $days++;
  }

  # Test durations of the form <number of days>+<hour>:<minute>
  for ($days = 0; $days < 3; $days++) {
    $self->assertDuration(($MINUTE * 15) + ($days * $DAY), "${days}+18:30");
    $self->assertDuration(($days * $DAY), "${days}+18:15");
    $self->assertDuration((($days + 1) * $DAY) - ($MINUTE * 15),
                          "${days}+18:00");
  }

  # Test durations of the form <YYYY>:<MM>:<DD>:<hh>:<mm>
  $self->assertDuration(($MINUTE * 15), '2013:07:05:18:30');
  $self->assertDuration(($HOUR * 2),    '2013:07:05:20:15');
  $self->assertDuration(($DAY * 3),     '2013:07:08:18:15');
  $self->assertDuration(($DAY * 31),    '2013:08:05:18:15');
  $self->assertDuration($YEAR,          '2014:07:05:18:15');
  eval {
    Permabit::Duration->new('2013:07:05:18:14', $START_TIME);
  };
  assertEvalErrorMatches(qr/Can\'t specify a time in the past!/);
}

1;
