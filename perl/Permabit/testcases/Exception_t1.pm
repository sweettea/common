##
# Test the Permabit::Exception module
#
# $Id$
##
package testcases::Exception_t1;

use strict;
use warnings FATAL => qw(all);
use Carp;
use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(
  assertEq
  assertFalse
  assertNumArgs
  assertRegexpDoesNotMatch
  assertRegexpMatches
  assertType
);
use Permabit::AsyncSub;
use Permabit::Exception qw(Type);
use Permabit::Utils qw(makeRandomToken);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

###############################################################################
##
sub testException {
  my ($self) = assertNumArgs(1, @_);

  # Test die($scalar)
  my $msg = makeRandomToken(9) . " scalar\n";
  eval { die($msg); };
  my $ee = $EVAL_ERROR;
  assertEq($msg, $ee);
  assertRegexpMatches(qr/\sscala/, $ee);
  assertRegexpDoesNotMatch(qr/foobar/, $ee);

  # Test die of an untyped Permabit::Exception
  $msg = makeRandomToken(9) . " exception";
  eval { die(Permabit::Exception->new($msg)); };
  $ee = $EVAL_ERROR;
  assertType("Permabit::Exception", $ee);
  assertRegexpMatches(qr/^$msg at /, $ee);
  assertRegexpDoesNotMatch(qr/foobar/, $ee);

  # Test die of a repeated untyped Permabit::Exception
  eval { die(Permabit::Exception->new($ee)); };
  $ee = $EVAL_ERROR;
  assertType("Permabit::Exception", $ee);
  assertRegexpMatches(qr/^$msg at /, $ee);
  assertRegexpDoesNotMatch(qr/foobar/, $ee);

  # Test croak($scalar)
  $msg = makeRandomToken(9) . " croak\n";
  eval { croak($msg); };
  $ee = $EVAL_ERROR;
  assertFalse(ref($ee));
  assertRegexpMatches(qr/^$msg at /, $ee);
  assertRegexpDoesNotMatch(qr/foobar/, $ee);

  # Test die of an untyped Permabit::Exception of a croak message
  $msg = $ee;
  eval { die(Permabit::Exception->new($ee)); };
  $ee = $EVAL_ERROR;
  assertType("Permabit::Exception", $ee);
  assertEq($msg, $ee);

  # Test die of a Permabit::Exception::Type
  $msg = makeRandomToken(9) . " typed exception";
  eval { die(Permabit::Exception::Type->new($msg)); };
  $ee = $EVAL_ERROR;
  assertType("Permabit::Exception", $ee);
  assertType("Permabit::Exception::Type", $ee);
  assertRegexpMatches(qr/^$msg at /, $ee);
  assertRegexpDoesNotMatch(qr/foobar/, $ee);

  # Test die of a Permabit::Exception::Type in a Permabit::AsyncSub
  $msg = makeRandomToken(9) . " async exception";
  my $code = sub {
    die(Permabit::Exception::Type->new($msg));
  };
  my $asub = Permabit::AsyncSub->new(code => $code);
  $asub->start();
  eval { $asub->result(); };
  $ee = $EVAL_ERROR;
  assertType("Permabit::Exception", $ee);
  assertType("Permabit::Exception::Type", $ee);
  assertRegexpMatches(qr/^$msg at /, $ee);
  assertRegexpDoesNotMatch(qr/foobar/, $ee);

  # Test croak of a Permabit::Exception::Type
  $msg = makeRandomToken(9) . " croaked exception";
  eval { croak(Permabit::Exception::Type->new($msg)); };
  $ee = $EVAL_ERROR;
  assertType("Permabit::Exception", $ee);
  assertType("Permabit::Exception::Type", $ee);
  assertRegexpMatches(qr/^$msg at /, $ee);
  assertRegexpDoesNotMatch(qr/foobar/, $ee);

  # Test confess of a Permabit::Exception::Type
  $msg = makeRandomToken(9) . " confessed exception";
  eval { confess(Permabit::Exception::Type->new($msg)); };
  $ee = $EVAL_ERROR;
  assertType("Permabit::Exception", $ee);
  assertType("Permabit::Exception::Type", $ee);
  assertRegexpMatches(qr/^$msg at /, $ee);
  assertRegexpDoesNotMatch(qr/foobar/, $ee);
}

1;
