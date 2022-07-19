##
# Implementation of LabUtils Configured-dependent methods.
#
# @synopsis
#
#     use Permabit::LabUtils::Implementation;
#
#     our $IMPLEMENTATION = Permabit::LabUtils::Implementation->new();
#
# @description
#
# This class should only be instantiated by the Permabit::LabUtils
# module. Alternate implementations should derive from it and be
# Configured for instantiation.
##
package Permabit::LabUtils::Implementation;

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

  # Defaults
  # LabMachine must come last.
  $self->{machineClasses} //= [
                               { class => 'Permabit::LabUtils::LabMachine',
                                 file  => undef },
                              ];
  $self->{virtualMachine} //= {};
  $self->{virtualMachine}->{name} //= {};
  $self->{virtualMachine}->{name}->{regex} //= '.+';
  # Default: Every FQDN is considered acceptable.
  $self->{virtualMachine}->{name}->{fqdnSuffixes} //= ['\..+$',];
}

1;
