##
# Test Permabit::VersionNumber.
#
# $Id$
##
package testcases::VersionNumber_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Permabit::Assertions qw(
  assertEq
  assertEqualNumeric
  assertNumArgs
);

use Permabit::VersionNumber qw(
  $FIRST_VERSION_NUMBER
  $LAST_VERSION_NUMBER
);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my $VERSION_STRING = '1.2.3.4';

######################################################################
##
sub testShorten {
  my ($self) = assertNumArgs(1, @_);
  $self->checkShortened('0.0.1.0', 1, 3, '0.0.1');
  $self->checkShortened('0.0.1.0', 2, 3, '0.0.1');
  $self->checkShortened('0.0.1.0', 2, 4, '0.0.1');
  $self->checkShortened('0.1.0.0', 1, 3, '0.1');
  $self->checkShortened('0.1.0.0', 2, 3, '0.1');
  $self->checkShortened('0.1.0.0', 2, 4, '0.1');
  $self->checkShortened('1.0.0.0', 1, 3, '1');
  $self->checkShortened('1.0.0.0', 2, 3, '1.0');
  $self->checkShortened('1.0.0.0', 2, 4, '1.0');
  $self->checkShortened('1.2.0.0', 1, 3, '1.2');
  $self->checkShortened('1.2.0.0', 2, 3, '1.2');
  $self->checkShortened('1.2.0.0', 2, 4, '1.2');
  $self->checkShortened('1.0.3.0', 1, 3, '1.0.3');
  $self->checkShortened('1.0.3.0', 2, 3, '1.0.3');
  $self->checkShortened('1.0.3.0', 2, 4, '1.0.3');
  $self->checkShortened('1.2.3.0', 1, 3, '1.2.3');
  $self->checkShortened('1.2.3.0', 2, 3, '1.2.3');
  $self->checkShortened('1.2.3.0', 2, 4, '1.2.3');
  $self->checkShortened('1.0.3.4', 1, 3, '1.0.3');
  $self->checkShortened('1.0.3.4', 2, 3, '1.0.3');
  $self->checkShortened('1.0.3.4', 2, 4, '1.0.3.4');
  $self->checkShortened('1.2.0.4', 1, 3, '1.2');
  $self->checkShortened('1.2.0.4', 2, 3, '1.2');
  $self->checkShortened('1.2.0.4', 2, 4, '1.2.0.4');
  $self->checkShortened('1.2.3.4', 1, 3, '1.2.3');
  $self->checkShortened('1.2.3.4', 2, 3, '1.2.3');
  $self->checkShortened('1.2.3.4', 2, 4, '1.2.3.4');

  eval {
    $FIRST_VERSION_NUMBER->shorten(2, 3);
    $self->fail("FIRST_VERSION_NUMBER->shorten() failed to throw")
  };

  eval {
    $LAST_VERSION_NUMBER->shorten(2, 3);
    $self->fail("LAST_VERSION_NUMBER->shorten() failed to throw")
  };
}

######################################################################
##
sub checkShortened {
  my ($self, $version, $min, $max, $expected) = assertNumArgs(5, @_);
  my $shortened
    = Permabit::VersionNumber->new($version)->shorten($min, $max);
  my $expectedVersion = Permabit::VersionNumber->new($expected);
  assertEq(($expected, "$shortened"));
  assertEq("$expectedVersion", "$shortened");
  assertEq($expectedVersion, $shortened);
  assertEqualNumeric($expectedVersion, $shortened);
}

######################################################################
##
sub testToString {
  my ($self) = assertNumArgs(1, @_);
  $self->checkToString(Permabit::VersionNumber->new($VERSION_STRING),
                       $VERSION_STRING, '1-2-3-4');
  $self->checkToString($FIRST_VERSION_NUMBER, 'FIRST_VERSION_NUMBER',
                       'FIRST_VERSION_NUMBER');
  $self->checkToString($LAST_VERSION_NUMBER, 'LAST_VERSION_NUMBER',
                       'LAST_VERSION_NUMBER');
}

######################################################################
##
sub checkToString {
  my ($self, $version, $stringified, $delimited) = assertNumArgs(4, @_);
  assertEq($stringified, "$version");
  assertEq($delimited, $version->toString('-'));
}

######################################################################
##
sub testSetComponent {
  my ($self) = assertNumArgs(1, @_);
  my $version = Permabit::VersionNumber->new($VERSION_STRING);
  assertEq('1.2.5.4', $version->setComponent(2, 5));
  assertEq($VERSION_STRING, $version);
  eval {
    $version->setComponent(4, 5);
    $self->fail("setComponent() failed to throw");
  };

  eval {
    $FIRST_VERSION_NUMBER->setComponent(1, 1);
    $self->fail("FIRST_VERSION_NUMBER->setComponent() failed to throw")
  };

  eval {
    $LAST_VERSION_NUMBER->setComponent(1, 1);
    $self->fail("LAST_VERSION_NUMBER->setComponent() failed to throw")
  };

}

######################################################################
##
sub testIncrement {
  my ($self) = assertNumArgs(1, @_);
  my $version = Permabit::VersionNumber->new($VERSION_STRING);
  assertEq('2.2.3.4', $version->increment(0));
  assertEq('1.3.3.4', $version->increment(1));
  assertEq('1.2.4.4', $version->increment(2));
  assertEq('1.2.3.5', $version->increment(3));
  assertEq('1.2.3.5', $version->increment());
  eval {
    $version->increment(4);
    $self->fail("increment() failed to throw");
  };

  assertEq($VERSION_STRING, $version);

  eval {
    $FIRST_VERSION_NUMBER->increment(1);
    $self->fail("FIRST_VERSION_NUMBER->increment() failed to throw")
  };

  eval {
    $LAST_VERSION_NUMBER->increment(1);
    $self->fail("LAST_VERSION_NUMBER->increment() failed to throw")
  };
}

######################################################################
##
sub testCompare {
  my ($self) = assertNumArgs(1, @_);
  $self->checkCompare($FIRST_VERSION_NUMBER, $FIRST_VERSION_NUMBER, 0);
  $self->checkCompare($FIRST_VERSION_NUMBER, $LAST_VERSION_NUMBER, -1);
  $self->checkCompare($LAST_VERSION_NUMBER, $LAST_VERSION_NUMBER, 0);

  my $version = Permabit::VersionNumber->new($VERSION_STRING);
  $self->checkCompare($version, $version, 0);
  $self->checkCompare($version, $FIRST_VERSION_NUMBER, 1);
  $self->checkCompare($version, $LAST_VERSION_NUMBER, -1);

  for (my $i = 0; $i < 4; $i++) {
    $self->checkCompare($version, $version->increment($i), -1);
  }

  # This is necessary because the undef literal doesn't compile on the lhs of
  # a comparison.
  my $undef;
  assertEqualNumeric(($version <=> $undef), 1);
  assertEqualNumeric(($undef <=> $version), -1);
  assertEqualNumeric(($version cmp $undef), 1);
  assertEqualNumeric(($undef cmp $version), -1);
  assertEqualNumeric(Permabit::VersionNumber::compare($undef, $undef, 0), 0);

  assertEqualNumeric(($FIRST_VERSION_NUMBER <=> $undef), 0);
  assertEqualNumeric(($undef <=> $FIRST_VERSION_NUMBER), 0);
  assertEqualNumeric(($FIRST_VERSION_NUMBER cmp $undef), 0);
  assertEqualNumeric(($undef cmp $FIRST_VERSION_NUMBER), 0);

  assertEqualNumeric(($LAST_VERSION_NUMBER <=> $undef), 0);
  assertEqualNumeric(($undef <=> $LAST_VERSION_NUMBER), 0);
  assertEqualNumeric(($LAST_VERSION_NUMBER cmp $undef), 0);
  assertEqualNumeric(($undef cmp $LAST_VERSION_NUMBER), 0);
}

######################################################################
# Test <=>, cmp, and ->compare all work as expected for a given pair of
# versions.
##
sub checkCompare {
  my ($self, $a, $b, $result) = assertNumArgs(4, @_);
  assertEqualNumeric(($a <=> $b), $result);
  assertEqualNumeric(($b <=> $a), $result * -1);
  assertEqualNumeric(($a cmp $b), $result);
  assertEqualNumeric(($b cmp $a), $result * -1);
  assertEqualNumeric($a->compare($b), $result);
  assertEqualNumeric($b->compare($a), $result * -1);
  assertEqualNumeric($a->compare($b, 1), $result * -1);
  assertEqualNumeric($b->compare($a, 1), $result);
}

1;
