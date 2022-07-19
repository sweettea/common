##
# This is an AsyncTask that will run a system command on a RemoteMachine.
#
# $Id$
##
package Permabit::AsyncTask::RunSystemCmd;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Permabit::Assertions qw(assertNumArgs);

use base qw(Permabit::AsyncTask);

###############################################################################
# Set up a new Permabit::AsyncTask::RunSystemCmd.
#
# @param machine  The Permabit::RemoteMachine.
# @param command  The command.
#
# @return the new Permabit::AsyncTask::RunSystemCmd.
##
sub new {
  my ($invocant, $machine, $command) = assertNumArgs(3, @_);
  my $self = $invocant->SUPER::new();
  $self->{machine} = $machine;
  $self->{command} = $command;
  $self->useMachine($machine);
  return $self;
}

###############################################################################
# @inherit
##
sub taskCode {
  my ($self) = assertNumArgs(1, @_);
  $self->{machine}->runSystemCmd($self->{command});
  return undef;
}

1;
