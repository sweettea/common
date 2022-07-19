##
# Base class for singletons representing special version numbers.
#
# @synopsis
#   use Permabit::VersionNumber qw($FIRST_VERSION_NUMBER);
#
# $Id$
##
package Permabit::VersionNumber::Special;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Carp qw(confess);

use Permabit::Assertions qw(
  assertMinMaxArgs
  assertNe
  assertNumArgs
);

# Can't 'use base' here because of circular dependencies.
our @ISA = qw(Permabit::VersionNumber);

######################################################################
# Construct a special version number.
#
# @param name  The name of the special version number
##
sub new {
  my ($invocant, $name) = assertNumArgs(2, @_);
  my $class = ref($invocant) || $invocant;
  # We are only used as a base class.
  assertNe(__PACKAGE__, $class);
  return bless { name => $name }, $class;
}

########################################################################
# Convert a special version to a string.
#
# @oparam delimiter  The component delimiter to use; defaults to '.'
#
# @return The version as a string
##
sub toString {
  my ($self, $delimiter) = assertMinMaxArgs(['.'], 1, 2, @_);
  return $self->{name};
}

######################################################################
# Check whether something is a VersionNumber::Special.
#
# @param thing  The thing to check
#
# @return true if thing is a VersionNumber::Special
##
sub isSpecialVersionNumber {
  my ($thing) = assertNumArgs(1, @_);
  return (ref($thing) && $thing->isa(__PACKAGE__));
}

########################################################################
# Cause all non-overriden base class methods to fail.
##
sub AUTOLOAD {
  our $AUTOLOAD;
  my $method = $AUTOLOAD;
  $method =~ s/.*:://;
  if ($method ne 'DESTROY') {
    confess("Can't call $method on $ARGV[0]");
  }
}

1;
