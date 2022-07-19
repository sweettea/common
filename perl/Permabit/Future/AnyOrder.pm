##
# A subclass of Permabit::Future that waits for a list of a
# Permabit::Future objects to complete in any order.
#
# @synopsis
#
#   # Create a sequence of future actions
#   use Permabit::Future::InOrder;
#   my @futures;
#   push(@futures, aFuture);  # First Future
#   push(@futures, bFuture);  # Second Future
#   push(@futures, cFuture);  # Third Future
#   my $dSub = sub { D(); };  # Code to do after all 3 futures finish
#   my $future = Permabit::Future::AnyOrder->new(finallyCode => $dSub,
#                                                list        => \@futures,);
#   while (!future->isDone()) {
#     # program does other stuff
#     $future->poll();
#   }
#
# $Id$
##
package Permabit::Future::AnyOrder;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Permabit::Assertions qw(assertDefined assertNumArgs);
use Storable qw(dclone);

use base qw(Permabit::Future);

#############################################################################
# @paramList{new}
my %properties = (
  # @ple A list of C<Permabit::Future> objects
  list => undef,
);
##

#############################################################################
# Creates a C<Permabit::Future::AnyOrder>.
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
  assertDefined($self->{list});
  return $self;
}

#############################################################################
# @inherit
##
sub addTime {
  my ($self, $adjustment) = assertNumArgs(2, @_);
  my @copy = @{$self->{list}};
  foreach my $f (@copy) {
    $f->addTime($adjustment);
  }
}

#############################################################################
# @inherit
##
sub getWhatFor {
  my ($self) = assertNumArgs(1, @_);
  my @copy = @{$self->{list}};
  return scalar(@copy)
    ? join(", and for ", map { $_->getWhatFor() } @copy)
    : "nothing";
}

#############################################################################
# @inherit
##
sub testTrigger {
  my ($self) = assertNumArgs(1, @_);
  my @copy = @{$self->{list}};
  foreach my $f (@copy) {
    $f->poll();
  }
  # Remove all completed Futures from the list.  This must use the
  # list directly, as it might have changed during the polling loop.
  # It is safe to use isDone(), which does not call user supplied
  # code.
  $self->{list} = [grep { !$_->isDone() } @{$self->{list}}];
  return scalar(@{$self->{list}}) == 0;
}

1;
