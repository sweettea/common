##
# A subclass of Permabit::Future that waits for a Permabit::AsyncSub
# to complete.
#
# @synopsis
#
#   # Run A asynchronously, then run B synchronously.
#   use Permabit::Future::AfterAsyncSub;
#   my $aThread = Permabit::AsyncSub->new(code => sub { A(); });
#   my $bFuture
#     = Permabit::Future::AfterAsyncSub->new(asyncSub    => aThread,
#                                            finallyCode => sub { B(); },
#                                            timeLimit   => 30 * $MINUTE,
#                                            whatFor     => "A");
#   $aThread->start();
#   while (!$bFuture->isDone()) {
#     # program does other stuff
#     $bFuture->poll();
#   }
#
# $Id$
##
package Permabit::Future::AfterAsyncSub;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Carp qw(confess);
use Permabit::Assertions qw(assertDefined assertNumArgs);
use Storable qw(dclone);

use base qw(Permabit::Future);

#############################################################################
# @paramList{new}
my %properties = (
  # @ple A C<Permabit::AsyncSub> object.
  asyncSub => undef,
  # @ple Code to run when asyncSub reports an error.
  #      If not specified, confess will be used.
  #      $EVAL_ERROR is valid when onError is called.
  onError => undef,
  # @ple Code to run when asyncSub reports no error.
  #      If not specified, a noop is used.
  onSuccess => undef,
);
##

#############################################################################
# Creates a C<Permabit::Future::AfterAsyncSub>.
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
  assertDefined($self->{asyncSub});
  return $self;
}

#############################################################################
# @inherit
##
sub testTrigger {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{asyncSub}->isComplete()) {
    eval { $self->{asyncSub}->result(); };
    my $onCode = $EVAL_ERROR ? $self->{onError} : $self->{onSuccess};
    if (defined($onCode)) {
      $onCode->();
    } elsif ($EVAL_ERROR) {
      my $error = $EVAL_ERROR;
      my $whatFor = $self->getWhatFor();
      confess("Error while waiting for $whatFor: $error");
    }
    return 1;
  }
  return 0;
}

1;
