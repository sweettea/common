##
# Test the Permabit::SupportUtils module
#
# $Id$
##
package testcases::SupportUtils_t1;

use strict;
use warnings FATAL => qw(all);
use Carp qw(croak);
use English qw(-no_match_vars);
use Fatal qw(mkdir);
use IO::File;
use POSIX qw(strftime);

use Permabit::Assertions qw(
  assertEq
  assertNumArgs
);
use Permabit::Constants;
use Permabit::SupportUtils qw(
  convertToEpoch
  convertToFormatted
);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
##
sub testConvertToEpoch {
  my ($self) = assertNumArgs(1, @_);
  my $date = [1970,01,01];
  my $time = [01,02,03];
  my $epoch = convertToEpoch($time, $date);
  my $timeString = strftime("%Y/%m/%d %H:%M:%S", localtime($epoch));
  assertEq("1970/01/01 01:02:03", $timeString);
}

######################################################################
##
sub testConvertToFormatted {
  my ($self) = assertNumArgs(1, @_);
  my $date = [1970,01,01];
  my $time = [01,02,03];
  my $epoch = convertToEpoch($time, $date);

  my $timeString = convertToFormatted($epoch);
  assertEq("1970/01/01 01:02", $timeString);

  $timeString = convertToFormatted($epoch, 1);
  assertEq("1970/01/01 01:02:03", $timeString);
}

1;
