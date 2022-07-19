##
# A singleton class representing a version number which is greater than
# all other versions. This class should only be used directly by
# Permabit::VersionNumber.
#
# @synopsis
#   use Permabit::VersionNumber qw($LAST_VERSION_NUMBER);
#
# $Id$
##
package Permabit::VersionNumber::Last;

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

my $LAST_VERSION_NUMBER;

########################################################################
# Get the single instance of this class.
#
# @return The last version number instance
##
sub get {
  my ($invocant) = assertNumArgs(1, @_);
  return ($LAST_VERSION_NUMBER
          //= Permabit::VersionNumber::Last->new('LAST_VERSION_NUMBER'));
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

  return ($reversed ? -1 : 1);
}

1;
