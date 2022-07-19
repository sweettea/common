##
# Implementation of Triage::TestInfo Configured-dependent methods.
#
# @synopsis
#
#     use Permabit::Triage::TestInfo::Implementation;
#
#     our $IMPLEMENTATION = Permabit::Triage::TestInfo::Implementation->new();
#
# @description
#
# This class should only be instantiated by the Permabit::Triage::TestInfo
# module. Alternate implementations should derive from it and be
# Configured for instantiation.
##

package Permabit::Triage::TestInfo::Implementation;

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
  # Implementation defaults
  $self->{albireoPerfHosts} //= [];
  $self->{vdoPerfHosts} //= [];
}

1;
