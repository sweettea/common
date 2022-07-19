##
# Implementation of CheckServer Constants Configured-dependent methods.
#
# @synopsis
#
#     use Permabit::CheckServer::Constants::Implementation;
#
#     our $IMPLEMENTATION
#       = Permabit::CheckServer::Constants::Implementation->new();
#
# @description
#
# This class should only be instantiated by the
# Permabit::CheckServer::Constants module. Alternate implementations should
# derive from it and be Configured for instantiation.
##

package Permabit::CheckServer::Constants::Implementation;

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
  $self->{nfs} //= {};
  $self->{triage} //= {};
}

1;
