##
# This module represents the pdoc2pod context when parsing a paramList
# entry.
#
# $Id$
##
package Pdoc::ParamList;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Permabit::Assertions qw(assertNumArgs);

######################################################################
# Create a new ParamList of the given name.
#
# @param listName       The name of this paramList
##
sub new {
  my ($invocant, $listName) = @_;
  my $class = ref($invocant) || $invocant;
  my $self = bless {
                    listName            => $listName,
                   }, $class;
  return $self;
}

######################################################################
# Add a new parameter to this parameter list
#
# @param name           The name of the parameter
# @param description    The description of that parameter
##
sub addParameter {
  assertNumArgs(3, @_);
  my ($self, $name, $description) = @_;
  $self->{params}->{$name} = $description;
}  

######################################################################
# Add this paramlist to the parameters for a given functions
#
# @param function       The function whose parameters this represents
##
sub insertInFunction {
  assertNumArgs(2, @_);
  my ($self, $function) = @_;
  foreach my $key (sort(keys(%{$self->{params}}))) {
    $function->addParameter($key, $self->{params}->{$key});
  }
}

1;
