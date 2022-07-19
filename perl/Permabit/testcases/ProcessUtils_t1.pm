##
# Test the ProcessUtils module
#
# $Id$
##
package testcases::ProcessUtils_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Permabit::Assertions qw(
  assertEq
  assertEqualNumeric
  assertEvalErrorMatches
  assertNumArgs
  assertRegexpMatches
);
use Permabit::ProcessUtils qw(delayFailures);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
##
sub testDelayFailures {
  my ($self) = assertNumArgs(1, @_);
  my $aCount = 0;
  my $aSub = sub { $aCount++; };
  my $bCount = 0;
  my $bSub = sub { $bCount++; };
  my $fail1 = sub { die("fail1"); };
  my $fail2 = sub { die("fail2"); };
  my $fail3 = sub { die("fail3"); };

  eval { delayFailures($aSub, $bSub); };
  assertEq("", $EVAL_ERROR);
  assertEqualNumeric(1, $aCount);
  assertEqualNumeric(1, $bCount);

  eval { delayFailures($fail1, $aSub, $bSub); };
  assertEvalErrorMatches(qr/^fail1 at /);
  assertEqualNumeric(2, $aCount);
  assertEqualNumeric(2, $bCount);

  eval { delayFailures($aSub, $fail2, $bSub); };
  assertEvalErrorMatches(qr/^fail2 at /);
  assertEqualNumeric(3, $aCount);
  assertEqualNumeric(3, $bCount);

  eval { delayFailures($aSub, $bSub, $fail3); };
  assertEvalErrorMatches(qr/^fail3 at /);
  assertEqualNumeric(4, $aCount);
  assertEqualNumeric(4, $bCount);

  eval { delayFailures($fail1, $aSub, $fail2, $bSub, $fail3); };
  my $ee = $EVAL_ERROR;
  assertRegexpMatches(qr/^3 delayed failures:/, $ee);
  assertRegexpMatches(qr/^fail1 at /m, $ee);
  assertRegexpMatches(qr/^fail2 at /m, $ee);
  assertRegexpMatches(qr/^fail3 at /m, $ee);
  assertEqualNumeric(5, $aCount);
  assertEqualNumeric(5, $bCount);
}

1;
