##
# A subclass of Permabit::Future that waits for a list of a
# Permabit::Future objects to complete in order.
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
#   my $future = Permabit::Future::InOrder->new(finallyCode => $dSub,
#                                               list        => \@futures,);
#   while (!future->isDone()) {
#     # program does other stuff
#     $future->poll();
#   }
#
# $Id$
##
package Permabit::Future::InOrder;

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
# Creates a C<Permabit::Future::InOrder>.
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
  my $list = $self->{list};
  scalar(@$list) && $list->[0]->addTime($adjustment);
}

#############################################################################
# @inherit
##
sub getWhatFor {
  my ($self) = assertNumArgs(1, @_);
  my $list = $self->{list};
  return scalar(@$list) ? $list->[0]->getWhatFor() : "nothing";
}

#############################################################################
# @inherit
##
sub testTrigger {
  my ($self) = assertNumArgs(1, @_);
  my $list = $self->{list};
  while (scalar(@$list)) {
    $list->[0]->poll();
    if (!$list->[0]->isDone()) {
      last;
    }
    shift(@$list);
  }
  return scalar(@$list) == 0;
}

1;
