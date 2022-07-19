##
# A base class which composes the PROPERTIES hashes of all classes in
# an object's class hierarchy. This class can be used as a base class,
# or as a mix in.
#
# @synopsis
#
#    package MyBaseClass;
#
#    use base qw(Permabit::Propertied);
#
#    our %PROPERTIES = (...);
#
#    sub new {
#      ...
#      # mixin
#      addToHash($self, $self->getClassProperties(@_));
#    }
#
# @description
#
# This class implements class hierarchy default properties by composing
# the %PROPERTIES hashse of the class hiearchy. It can be used as a base
# class by calling the new() method, or it can be used as a mix-in by
# calling getClassProperties() directly.
#
# $Id$
##
package Permabit::Propertied;

use strict;
use warnings FATAL => qw(all);
use Carp;
use English qw(-no_match_vars);
use Storable qw(dclone);

use Permabit::Assertions qw(assertMinArgs assertNumArgs);
use Permabit::ClassUtils qw(getClassHash);

###########################################################################
# Create a new object with a hierarchy of properties.
##
sub new {
  my ($invocant, %parameters) = assertMinArgs(1, @_);
  my $class = ref($invocant) || $invocant;
  return bless { %{getClassProperties($invocant, %parameters)} }, $class;
}

###########################################################################
# Compose hashes from a class hierarchy.
#
# @param invocant  The class or object whose hierarchy is desired
# @param hash      The name of the hash
#
# @return A hashref of properties which has been cloned for safety
##
sub cloneClassHash {
  my ($invocant, $hash) = assertNumArgs(2, @_);
  my $class = ref($invocant) || $invocant;
  return dclone(getClassHash($class, $hash));
}

###########################################################################
# Compose the PROPERTIES hashes from a class hierarchy.
#
# @param  invocant    The class or object whose hierarchy is desired
# @oparam parameters  Overrides of default parameters
#
# @return A hashref of properties which has been cloned for safety
##
sub getClassProperties {
  my ($invocant, %parameters) = assertMinArgs(1, @_);
  return dclone({
                 %{getClassHash($invocant, "PROPERTIES")},
                 %parameters,
                });
}

1;
