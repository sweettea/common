##
# Methods for manipulating version numbers.
#
# @synopsis
#   use Permabit::VersionNumber;
#
#   my $version = VersionNumber->new('1.2.3.4')->increment();
#   print($version);
#
# $Id$
##
package Permabit::VersionNumber;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use List::Util qw(min);

use Permabit::Assertions qw(
  assertMinMaxArgs
  assertNumArgs
);
use Permabit::VersionNumber::First;
use Permabit::VersionNumber::Last;
use Permabit::VersionNumber::Special qw(isSpecialVersionNumber);

use base qw(Exporter);

our @EXPORT_OK = qw(
  $FIRST_VERSION_NUMBER
  $LAST_VERSION_NUMBER
  isVersionNumber
);

our $FIRST_VERSION_NUMBER = Permabit::VersionNumber::First->get();
our $LAST_VERSION_NUMBER  = Permabit::VersionNumber::Last->get();

use overload
  '""'  => sub { return $_[0]->toString() },
  '<=>' => \&compare,
  'cmp' => \&compare;

######################################################################
# Create a new version.
#
# @param version     The value of the version either as a string or an array of
#                    components
# @oparam delimiter  The component delimiter, defaults to '\.'.
#
# @return A new version
##
sub new {
  my ($invocant, $version, $delimiter) = assertMinMaxArgs(['\.'], 2, 3, @_);
  my $class      = ref($invocant) || $invocant;
  my $components = (ref($version) ? $version : [split($delimiter, $version)]);
  return bless {
    components => $components,
    length     => scalar(@{$components}),
  }, $class;
}

######################################################################
# Create a new version if the input has the specified number of components
#
# @param  invocant    The package or object of the type to create
# @param  version     The value of the version either as a string or an array of
#                     components or a VersionNumber
# @param  components  The required number of components
# @oparam delimiter   The component delimiter, defaults to '\.'.
#
# @return A new version or undef if the input does not have the requisite
#         number of components
##
sub makeIfVersion {
  my ($invocant, $version, $components, $delimiter)
    = assertMinMaxArgs(['\.'], 3, 4, @_);
  if (!defined($version)) {
    return undef;
  }

  if (isVersionNumber($version)) {
    return $version->new("$version");
  }

  if (!ref($version)) {
    $version = [split($delimiter, $version)];
  }

  return ((scalar(@{$version}) == $components)
          ? $invocant->new($version) : undef);
}

######################################################################
# Make a shortened version which contains only some of the components.
#
# @param minimum  The minimum number of components for the shortened version
# @param maximum  The maximum number of components for the shortened version
#
# @return A shortened version derived from this version
##
sub shorten {
  my ($self, $minimum, $maximum) = assertNumArgs(3, @_);
  $self->validateComponent($maximum - 1);
  while (--$maximum >= $minimum) {
    if ($self->{components}[$maximum] != 0) {
      last;
    }
  }
  return $self->new([@{$self->{components}}[0..$maximum]]);
}

######################################################################
# Convert a version to a string.
#
# @oparam delimiter  The component delimiter to use; defaults to '.'
#
# @return The version as a string
##
sub toString {
  my ($self, $delimiter) = assertMinMaxArgs(['.'], 1, 2, @_);
  return join($delimiter, @{$self->{components}});
}

######################################################################
# Check whether a component index is valid. Will die if not.
#
# @param component  The component index to validate
##
sub validateComponent {
  my ($self, $component) = assertNumArgs(2, @_);
  if ($component >= $self->{length}) {
    die("Invalid component $component, version only has $self->{length}");
  }
}

######################################################################
# Set the component of a version.
#
# @param component  The component to set
# @param value      The value to set
#
# @return A new version with the indicated component modified
##
sub setComponent {
  my ($self, $component, $value) = assertNumArgs(3, @_);
  $self->validateComponent($component);

  my @components = @{$self->{components}};
  $components[$component] = $value;
  return $self->new([@components]);
}

######################################################################
# Increment the version.
#
# @oparam component  The component of the version to increment; defaults to
#                    the last component
#
# @return A new version which has been incremented
##
sub increment {
  my ($self, $component) = assertMinMaxArgs([-1], 1, 2, @_);
  return $self->setComponent($component, $self->{components}[$component] + 1);
}

######################################################################
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
  my $sense = ($reversed ? -1 : 1);
  if (!defined($self)) {
    return (defined($other) ? -1 : 0) * $sense;
  }

  if (!defined($other)) {
    return (defined($self) ? 1 : 0) * $sense;
  }

  if (Permabit::VersionNumber::Special::isSpecialVersionNumber($other)) {
    return $other->compare($self, !$reversed);
  }

  if (!isVersionNumber($other)) {
    $other = $self->new($other);
  }

  my $length = min($self->{length}, $other->{length});
  for (my $i = 0; $i < $length; $i++) {
    my $cmp = ($self->{components}[$i] <=> $other->{components}[$i]);
    if ($cmp != 0) {
      return $cmp * $sense;
    }
  }

  return ($self->{length} <=> $other->{length}) * $sense;
}

######################################################################
# Check whether something is a VersionNumber.
#
# @param thing  The thing to check
#
# @return true if thing is a VersionNumber
##
sub isVersionNumber {
  my ($thing) = assertNumArgs(1, @_);
  return (ref($thing) && $thing->isa(__PACKAGE__));
}

1;
