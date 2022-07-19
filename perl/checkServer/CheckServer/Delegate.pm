##
# Base class for classes which are delegates.
#
# $Id$
##
package CheckServer::Delegate;

use strict;
use warnings FATAL => qw(all);

use Carp;
use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(
  assertMinArgs
  assertNumArgs
);

our $AUTOLOAD;

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
sub can {
  my ($self, $method) = assertNumArgs(2, @_);
  my $install = join('::', ref($self), $method);
  return ($self->SUPER::can($method) || $self->load($method, $install));
}

########################################################################
# A method to load a method on behalf of AUTOLOAD() or can() which does not
# invoke the method but only installs it. Derived classes must override this
# method.
#
# @param method  The name of the method
#
# @return Whether or not the method was loaded
##
sub load {
  my ($self, $method, $install) = assertNumArgs(3, @_);
  return 0;
}

########################################################################
sub AUTOLOAD {
  my ($self, @rest) = assertMinArgs(1, @_);
  my $method = (split(/::/, $AUTOLOAD))[-1];
  if ($method eq 'DESTROY') {
    return;
  }

  if ($self->load($method, $AUTOLOAD)) {
    $log->info(ref($self) . " loaded $AUTOLOAD");
    goto &{$AUTOLOAD};
  }

  confess("Couldn't load $AUTOLOAD on $self");
}

1;

