##
# Represents a location in the source.
#
# $Id$
##
package Pdoc::Location;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Permabit::Assertions qw(assertNumArgs);

######################################################################
# Create a new Location for a given file
#
# @param fileName  The name of the file.
##
sub new {
  my ($invocant, $fileName) = @_;
  my $class = ref($invocant) || $invocant;
  my $self = bless {
                    fileName   => $fileName,
                    lineNumber => 0,
                   }, $class;
  return $self;
}

######################################################################
# Advance to the next line.
##
sub advanceLine {
  my ($self) = assertNumArgs(1, @_);
  ++$self->{lineNumber};
}

######################################################################
# Return the current line number
##
sub getLineNumber {
  my ($self) = assertNumArgs(1, @_);
  return $self->{lineNumber};
}

######################################################################
# Return a string representation.
##
sub toString {
  my ($self) = assertNumArgs(1, @_);
  return $self->{fileName} . ":" . $self->{lineNumber} . ": ";
}

1;
