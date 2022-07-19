##
# Implementation of CheckServer Utils Configured-dependent methods.
#
# @synopsis
#
#     use Permabit::CheckServer::Utils::Implementation;
#
#     our $IMPLEMENTATION
#       = Permabit::CheckServer::Utils::Implementation->new();
#
# @description
#
# This class should only be instantiated by the
# Permabit::CheckServer::Utils module. Alternate implementations should
# derive from it and be Configured for instantiation.
##

package Permabit::CheckServer::Utils::Implementation;

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
  $self->{dns} //= {};
  $self->{hostname} //= {};
}

1;
