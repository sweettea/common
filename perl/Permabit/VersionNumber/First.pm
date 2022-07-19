##
# A singleton class representing a version number which is less than
# all other versions. This class should only be used directly by
# Permabit::VersionNumber.
#
# @synopsis
#   use Permabit::VersionNumber qw($FIRST_VERSION_NUMBER);
#
# $Id$
##
package Permabit::VersionNumber::First;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Carp qw(confess);

use Permabit::Assertions qw(
  assertMinMaxArgs
  assertNumArgs
);

use base qw(Permabit::VersionNumber::Special);

use overload
  '""'  => sub { return $_[0]->toString() },
  '<=>' => \&compare,
  'cmp' => \&compare;

my $FIRST_VERSION_NUMBER;

########################################################################
# Get the single instance of this class.
#
# @return The first version number instance
##
sub get {
  my ($invocant) = assertNumArgs(1, @_);
  return ($FIRST_VERSION_NUMBER
          //= Permabit::VersionNumber::First->new('FIRST_VERSION_NUMBER'));
}

########################################################################
# Compare a version to this version.
#
# @param  other     The version to compare
# @oparam reversed  Whether the operands have been reversed
#
# @return -1, 0, or 1 depending on whether this version is less than, equal to,
#         or greater than the other
##
sub compare {
  my ($self, $other, $reversed) = assertMinMaxArgs([], 2, 3, @_);
  if (!defined($other) || (ref($other) && $other->isa(__PACKAGE__))) {
    return 0;
  }

  return ($reversed ? 1 : -1);
}

1;
