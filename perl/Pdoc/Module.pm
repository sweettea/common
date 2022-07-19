##
# This module represents the pdoc2pod context when parsing a
# Module/Package.
#
# @bugs
# This class doesn't handle multiple inheritance very well.
#
# $Id$
##
package Pdoc::Module;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Carp qw(croak);
use Permabit::Assertions qw(assertNumArgs);
use Storable qw(dclone);

use base qw(Pdoc::File);

my %properties = (
                  base => undef,
                 );

######################################################################
# Create a new module
##
sub new {
  my $proto = shift(@_);
  my $class = ref($proto) || $proto;
  return $class->SUPER::new(%{ dclone(\%properties) }, @_);
}

######################################################################
# Set the base class of this module.
#
# @param base   Text describing the base class of this module
##
sub setBase {
  my ($self, $base) = assertNumArgs(2, @_);
  $self->{base} = $base;
}

######################################################################
# Get the base class of this module.
#
# @return A string containing the base class of this module
##
sub getBase {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{base}) {
    return $self->{base};
  } else {
    croak("No base set for module $self->{name}");
  }
}

######################################################################
# Insert base class information (if any) in POD description.
#
# @inherit
##
sub toString {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{base}) {
    my $output = "\n\n=head1 BASE CLASS\n\n";
    my @bases = split('\s', $self->{base});
    foreach my $base (@bases) {
      $output .= "Extends L<$base|$base>\n";
    }
    $self->{summary} .= $output;
  }
  return $self->SUPER::toString();
}

1;
