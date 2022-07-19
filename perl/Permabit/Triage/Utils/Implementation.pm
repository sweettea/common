##
# Implementation of Triage::TestInfo Configured-dependent methods.
#
# @synopsis
#
#     use Permabit::Triage::Utils::Implementation;
#
#     our $IMPLEMENTATION = Permabit::Triage::Utils::Implementation->new();
#
# @description
#
# This class should only be instantiated by the Permabit::Triage::TestInfo
# module. Alternate implementations should derive from it and be
# Configured for instantiation.
##

package Permabit::Triage::Utils::Implementation;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Log::Log4perl;
use Permabit::Assertions qw(assertNumArgs);

use base qw(Permabit::Configured);

# Log4perl Logging object
my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
# @inherit
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);
  $self->SUPER::initialize(@_);

  # Defaults
  $self->{graphing} //= {};
  $self->{jira} //= {};
}

1;
