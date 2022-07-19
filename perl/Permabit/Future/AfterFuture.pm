##
# A subclass of Permabit::Future that links to another
# Permabit::Future.  This allows an additional timeout or additional
# code to be added to an existing Permabit::Future.
#
# @synopsis
#
#   # Add more finally code to a Future action
#   use Permabit::Future::AfterFuture;
#   my $aFuture = routineThatReturnsAFuture();
#   my $aSub = sub { A(); };
#   my $future = Permabit::Future::AfterFuture->new(finallyCode => $aSub,
#                                                   future      => $aFuture,);
#   while (!future->isDone()) {
#     # program does other stuff
#     $future->poll();
#   }
#
# $Id$
##
package Permabit::Future::AfterFuture;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Permabit::Assertions qw(assertDefined assertNumArgs);
use Storable qw(dclone);

use base qw(Permabit::Future);

#############################################################################
# @paramList{new}
my %properties = (
  # @ple A C<Permabit::Future> object
  future => undef,
);
##

#############################################################################
# Creates a C<Permabit::Future::AfterFuture>.
#
# @params{new}
##
sub new {
  my $invocant = shift;
  my $class = ref($invocant) || $invocant;
  my $self = Permabit::Future::new($invocant,
                                   %{ dclone(\%properties) },
                                   # Overrides previous values
                                   @_,);
  assertDefined($self->{future});
  return $self;
}

#############################################################################
# @inherit
##
sub addTime {
  my ($self, $adjustment) = assertNumArgs(2, @_);
  $self->{future}->addTime($adjustment);
}

#############################################################################
# @inherit
##
sub getWhatFor {
  my ($self) = assertNumArgs(1, @_);
  return $self->{future}->getWhatFor();
}

#############################################################################
# @inherit
##
sub testTrigger {
  my ($self) = assertNumArgs(1, @_);
  $self->{future}->poll();
  return $self->{future}->isDone();
}

1;
