##
# A set of utility methods for class hierarchies.
#
# @synopsis
#
#    use ClassUtils qw(getClassArray);
#
#    my @classValues = getClassArray('className', 'VALUES');
#
# @description
#
# This class implements class methods which operate on class hierarchies.
#
# $Id$
##
package Permabit::ClassUtils;

use strict;
use warnings FATAL => qw(all);
use Carp;
use English qw(-no_match_vars);
use Storable qw(dclone);

use Permabit::Assertions qw(
  assertMinMaxArgs
  assertNumArgs
);

use base qw(Exporter);

our @EXPORT_OK = qw(
  getClassArray
  getClassHash
  getClassHashKeys
  getClassHierarchy
);

###########################################################################
# Compose arrays from a class hierarchy.
#
# @param  invocant  The class to explore or an object of that class
# @param  array     The name of the array
# @oparam clone     If true, return a clone of the compostion
#
# @return A arrayref which consists of the union of all the arrays of the given
#         name defined in all the classes of the class hierarchy of the specied
#         class
##
sub getClassArray {
  my ($invocant, $array, $clone) = assertMinMaxArgs([0], 2, 3, @_);
  no strict 'refs';
  my $result = [ map { @{"$_\::$array"} } getClassHierarchy($invocant) ];
  return ($clone ? dclone($result) : $result);
}

###########################################################################
# Compose hashes from a class hierarchy.
#
# @param  invocant  The class to explore or an object of that class
# @param  hash      The name of the hash
# @oparam clone     If true, return a clone of the compostion
#
# @return A hashref which consists of the union of all the hashes of the given
#         name defined in all the classes of the class hierarchy of the specied
#         class
##
sub getClassHash {
  my ($invocant, $hash, $clone) = assertMinMaxArgs([0], 2, 3, @_);
  no strict 'refs';
  my $result = { map { %{"$_\::$hash"} } getClassHierarchy($invocant) };
  return ($clone ? dclone($result) : $result);
}

######################################################################
# Get the keys from a compostion of hashes from a class hierarchy.
#
# @param  invocant  The class to explore or an object of that class
# @param  hash      The name of the hash
#
# @return The keys from the composed hashes
##
sub getClassHashKeys {
  return keys(%{ getClassHash(@_) });
}

###########################################################################
# Get the class hierarchy.
#
# @param invocant  The class to explore or an object of that class
#
# @return the class hierarchy of an object
##
sub getClassHierarchy {
  my ($invocant) = assertNumArgs(1, @_);
  my %seen      = ();
  my @hierarchy = ();
  foreach my $class (getFullClassHierarchy($invocant)) {
    if ($seen{$class}) {
      next;
    }
    push(@hierarchy, $class);
    $seen{$class} = 1;
  }

  return @hierarchy;
}

###########################################################################
# Get the full class hierarchy of a package (some classes may appear
# more than once).
#
# @param invocant  The class to explore or an object of that class
#
# @return the unfiltered class hierarchy of the specified object or class
##
sub getFullClassHierarchy {
  my ($invocant) = assertNumArgs(1, @_);
  my $package    = ref($invocant) || $invocant;
  no strict 'refs';
  return (map({ getFullClassHierarchy($_) } @{"$package\::ISA"}), $package);
}

1;
