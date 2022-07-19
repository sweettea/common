##
# A subclass of Permabit::Future that manages a mutating list of
# future actions.  Code can add future actions at any time.  When an
# action is done, it is removed from the list.
#
# @synopsis
#
#   # Run a general list of timers
#   use Permabit::Future::List;
#   use Permabit::Future::Timer;
#   my $futureList = Permabit::Future::List->new();
#   $futureList->add(Permabit::Future::Timer->new(code         => sub { A(); },
#                                                 timeInterval => 90);
#   $futureList->add(Permabit::Future::Timer->new(code         => sub { B(); },
#                                                 timeInterval => 9 * $MINUTE);
#   $futureList->add(Permabit::Future::Timer->new(code         => sub { C(); },
#                                                 timeInterval => 1 * $HOUR);
#   while (1) {
#     $futureList->poll();
#     # program does other stuff
#   }
#
# $Id$
##
package Permabit::Future::List;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Permabit::Assertions qw(assertMinArgs assertNumArgs);

use base qw(Permabit::Future);

#############################################################################
# Creates a C<Permabit::Future::List>. C<new> optionally takes
# arguments which are C<Permabit::Future> objects to put into the
# list.
#
# @oparam future  One or more C<Permabit::Future> objects
##
sub new {
  my ($invocant, @futures) = assertMinArgs(1, @_);
  my $self = Permabit::Future::new($invocant, _list => []);
  $self->add(@futures);
  return $self;
}

#############################################################################
# Add a list of C<Permabit::Future> objects.
#
# @oparam futures  C<Permabit::Future> objects.
##
sub add {
  my ($self, @futures) = assertMinArgs(1, @_);
  push(@{$self->{_list}}, @futures);
}

#############################################################################
# @inherit
##
sub addTime {
  my ($self, $adjustment) = assertNumArgs(2, @_);
  my @list = @{$self->{_list}};
  foreach my $f (@list) {
    $f->addTime($adjustment);
  }
}

#############################################################################
# Apply a function to all C<Permabit::Future> objects in the list.
#
# @param  code  Code to apply to each C<Permabit::Future> object.
##
sub apply {
  my ($self, $code) = assertNumArgs(2, @_);
  my @list = @{$self->{_list}};
  for my $f (@list) {
    $f->isa(__PACKAGE__) ? $f->apply($code) : $code->($f);
  }
}

#############################################################################
# Get the number of objects in the list.
#
# @return number of objects in the list.
##
sub count {
  my ($self) = assertNumArgs(1, @_);
  return scalar(@{$self->{_list}});
}

#############################################################################
# Get the list of objects.
#
# @return list of objects.
##
sub getList {
  my ($self) = assertNumArgs(1, @_);
  return @{$self->{_list}};
}

#############################################################################
# @inherit
#
# Polls the list of objects, and prunes completed objects from the list
##
sub poll {
  my ($self) = assertNumArgs(1, @_);
  # Copy the list!
  my @list = @{$self->{_list}};
  foreach my $f (@list) {
    # Inside this poll() the original list can be changed!
    $f->poll();
  }
  # Remove all completed Futures from the list.  This must use
  # $self->{_list} directly, and NOT the copy, as it might have
  # changed during the polling loop.  It is safe to use isDone(),
  # which does not call user supplied code.
  $self->{_list} = [grep { !$_->isDone() } @{$self->{_list}}];
}

#############################################################################
# @inherit
##
sub testDonePolling {
  my ($self) = assertNumArgs(1, @_);
  return($self->count() == 0);
}

1;
