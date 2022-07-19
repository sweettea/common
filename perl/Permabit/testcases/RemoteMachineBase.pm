##
# Base class for any test that uses a Permabit::RemoteMachine
#
# $Id$
##
package testcases::RemoteMachineBase;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Permabit::Assertions qw(assertNumArgs);
use Permabit::RemoteMachine;

use base qw(Permabit::Testcase);

##
# @paramList{new}
our %PROPERTIES
  = (
     # @ple The RSVP class to reserve from
     hostClass => undef,
     # @ple The host names to use
     hostNames => [],
     # @ple The Permabit::RemoteMachine
     machine   => undef,
     # @ple The number of hosts to reserve
     numHosts  => 1,
    );
##

###############################################################################
# @inherit
##
sub set_up {
  my ($self) = assertNumArgs(1, @_);
  $self->SUPER::set_up();
  $self->reserveHostGroup("host");
  my $hostname = $self->{hostNames}[0];
  $self->{machine} = Permabit::RemoteMachine->new(hostname => $hostname);
}

###############################################################################
# @inherit
##
sub tear_down {
  my ($self) = assertNumArgs(1, @_);
  if (defined($self->{machine})) {
    $self->{machine}->close();
  }
  $self->SUPER::tear_down();
}

1;
