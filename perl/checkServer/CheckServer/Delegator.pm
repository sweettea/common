##
# Base class for classes which delegate to other classes.
#
# $Id$
##
package CheckServer::Delegator;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(
  assertMinArgs
  assertNumArgs
);

use base qw(CheckServer::Delegate);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# Create a new object and specify the object which will be the delegate.
##
sub new {
  my ($pkg, $delegate, %properties) = assertMinArgs(2, @_);
  my $self = bless { %properties }, $pkg;
  $self->setDelegate($delegate);
  return $self;
}

########################################################################
# Specify the delegate. This is broken out so that it can be called from
# initialize() for derived classes which are also Configured.
#
# @param delegate  The object to which undefined methods will be delegated
##
sub setDelegate {
  my ($self, $delegate) = assertNumArgs(2, @_);

  if (exists $self->{_delegate}) {
    die("$self already has a delegate");
  }

  $self->{_delegate} = $delegate;
}

########################################################################
# @inherit
##
sub load {
  my ($self, $method, $install) = assertNumArgs(3, @_);
  if (!$self->{_delegate}->can($method)) {
    return 0;
  }

  no strict 'refs';
  *{$install} = sub {
    my ($self, @rest) = assertMinArgs(1, @_);
    $self->{_delegate}->$method(@rest);
  };
  return 1;
}

1;

