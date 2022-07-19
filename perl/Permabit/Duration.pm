######################################################################
# Specify a length of time in many formats.
#
# @synopsis
#
#     use Permabit::Duration;
#
#     my $duration = Permabit::Duration->new('10s');
#     my $endTime  = $timeSpec->endTime();
#
# @description
#
# Permabit::Duration allows users to specify the start and end of a length of
# time.
#
# The start time is specified as a number of seconds since the epoch. It will
# default to the current time if not specified.
#
# The formats for the end time are as follows:
#
# @level{+}
#
# @item [number of seconds since the epoch]
#
# An absolute end time specified as an absolute number of seconds since the
# epoch.
#
# @item [number][unit]
#
# A simple length of time. A number followed by one of s, m, h, d, or
# w for seconds, minutes, hours, days, or weeks respectively. For
# example, 10m means 10 minutes.
#
# @item [day][hour]:[minute]
#
# A time of day on a given day. A single letter representing a day of the
# week (S, M, T, W, R, F, A starting at Sunday) followed by a numeric
# hour and minute. For example, F15:34 means the first 3:34 PM on a
# Friday after the start time.
#
# @item [number of days]+[hour]:[minute]
#
# A time of day a given number of days in the future. A number
# followed by a numeric hour and minute. For example, 3+15:34 means
# the first 3:34 PM at least three days from now. If it is now 3:00 PM
# on a Friday, this will by 3:34 PM on the next Monday. However, if it
# is 3:40 PM on a Friday, this will be 3:34 PM on the next Tuesday.
#
#
# @item [YYYY]:[MM]:[DD]:[hh]:[mm]
#
# An absolute end time. Numeric year, month, day, hour, and
# minute. For example, 2014:01:01:12:00 will end at noon on new year's
# day, 2014.
#
# @level{-}
#
# It is an error to specify a duration whose end time is earlier than
# its start time.
#
# $Id$
##
package Permabit::Duration;

use strict;
use warnings FATAL => qw(all);

use Carp;
use English qw(-no_match_vars);

use Date::Parse;
use POSIX qw(strftime);

use Permabit::Assertions qw(assertMinMaxArgs
                            assertNumArgs);
use Permabit::Constants;

my %DURATIONS = (s => 1,
                 m => $MINUTE,
                 h => $HOUR,
                 d => $DAY,
                 w => $DAY * 7,
                );

my %DAYS_DIFFERENCE = (S => [0, 6, 5, 4, 3, 2, 1],
                       M => [1, 0, 6, 5, 4, 3, 2],
                       T => [2, 1, 0, 6, 5, 4, 3],
                       W => [3, 2, 1, 0, 6, 5, 4],
                       R => [4, 3, 2, 1, 0, 6, 5],
                       F => [5, 4, 3, 2, 1, 0, 6],
                       A => [6, 5, 4, 3, 2, 1, 0],
                      );

######################################################################
# Create a new time specification.
#
# @param  duration   How long this duration lasts
# @oparam startTime  The time at which the duration will start if not
#                    supplied defaults to the current time
##
sub new {
  my ($pkg, $spec, $startTime) = assertMinMaxArgs([time()], 2, 3, @_);
  $spec =~ s/\s//g;

  my $self = bless { spec      => $spec,
                     startTime => $startTime
                   }, $pkg;

  $self->parse();
  if ($self->endTime() < $self->{startTime}) {
    croak("Can't specify a time in the past!");
  }
  return $self;
}

sub parse {
  my ($self) = assertNumArgs(1, @_);

  if ($self->{spec} =~ /^\d+$/) {
    $self->{endTime} = $self->{spec};
    return;
  }

  if ($self->{spec} =~ /^(\d+)([smhdw])$/) {
    $self->{duration} = ($1 * $DURATIONS{$2});
    return;
  }

  if ($self->{spec} =~ /^([SMTWRFA])(\d+):(\d+)/) {
    my ($weekDay, $hour, $minute) = ($1, $2, $3);
    my @now     = localtime($self->{startTime});
    my $difference = (($DAYS_DIFFERENCE{$weekDay}->[$now[6]] * $DAY)
        + (($hour - $now[2]) * $HOUR)
        + (($minute - $now[1]) * $MINUTE));
    if ($difference < 0) {
      $difference += ($DAY * 7);
    }
    $self->{duration} = $difference;
    return
  }

  if ($self->{spec} =~ /^(\d+)\+(\d+):(\d+)/) {
    my ($days, $hour, $minute) = ($1, $2, $3);
    my @now         = localtime($self->{startTime});
    my $difference = ((($hour - $now[2]) * $HOUR)
        + (($minute - $now[1]) * $MINUTE));
    if ($difference < 0) {
      $days++;
    }
    $self->{duration} = $difference + ($days * $DAY);
    return
  }

  my $endTime = str2time($self->{spec});
  if (!$endTime) {
    croak("Invalid time spec: ", $self->{spec});
  }
  $self->{endTime} = $endTime;
}

######################################################################
# Get the number of seconds from a given start time until the end of the
# duration.
#
# @oparam startTime The time from which the duration is desired. If not
#                   specified, the start time of the duration will be used.
#
# @return The time from the specified start time until the end time of the
#         duration in seconds (may be negative)
##
sub durationSeconds {
  my ($self, $startTime) = assertMinMaxArgs(1, 2, @_);
  $startTime //= $self->{startTime};
  return $self->endTime() - $startTime;
}

######################################################################
# Get the time at which this duration will end.
#
# @return The end time of this duration in seconds since the epoch
##
sub endTime {
  my ($self) = assertNumArgs(1, @_);
  $self->{endTime} //= ($self->{startTime} + $self->{duration});
  return $self->{endTime};
}

######################################################################
# Get the time at which this duration will end as a formatted string.
#
# @param format  An strftime() format string
#
# @return The end time of this duration formatted as specified
##
sub formatEndTime {
  my ($self, $format) = assertNumArgs(2, @_);
  return strftime($format, localtime($self->endTime()));
}

1;
