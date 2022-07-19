##
# Implementation of MainConstants Configured-dependent methods.
#
# @synopsis
#
#     use Permabit::MainConstants::Implementation;
#
#     our $IMPLEMENTATION = Permabit::MainConstants::Implementation->new();
#
# @description
#
# This class should only be instantiated by the
# Permabit::MainConstants module. Alternate implementations should
# derive from it and be Configured for instantiation.
##

package Permabit::MainConstants::Implementation;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Permabit::Assertions qw(assertNumArgs);
use Socket;

use base qw(Permabit::Configured);

######################################################################
# @inherit
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);
  $self->SUPER::initialize();

  # Implementation defaults
  $self->{users} //= {};
  $self->{users}->{human} //= {};
  $self->{users}->{nonHuman} //= ();
}

1;
