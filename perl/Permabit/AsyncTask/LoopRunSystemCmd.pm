##
# This is an AsyncTask that will run a system command on a RemoteMachine in a
# loop.
#
# $Id$
##
package Permabit::AsyncTask::LoopRunSystemCmd;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Log::Log4perl;
use Permabit::Assertions qw(assertNumArgs);

use base qw(Permabit::AsyncTask);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

###############################################################################
# Set up a new Permabit::AsyncTask::LoopRunSystemCmd.
#
# @param machine  The Permabit::RemoteMachine
# @param name     Name of the task
# @param count    Loop count
# @param command  The command
#
# @return the new Permabit::AsyncTask::LoopRunSystemCmd
##
sub new {
  my ($invocant, $machine, $name, $count, $command) = assertNumArgs(5, @_);
  my $self = $invocant->SUPER::new();
  $self->{machine} = $machine;
  $self->{name}    = $name;
  $self->{count}   = $count;
  $self->{command} = $command;
  $self->useMachine($machine);
  return $self;
}

###############################################################################
# @inherit
##
sub taskCode {
  my ($self) = assertNumArgs(1, @_);
  foreach my $i (1 .. $self->{count}) {
    $log->info("$self->{name} iteration $i");
    $self->{machine}->runSystemCmd($self->{command});
  }
  return undef;
}

1;
