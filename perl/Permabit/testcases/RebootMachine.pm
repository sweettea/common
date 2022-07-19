##
# Test rebooting a machine.
#
# $Id$
##
package testcases::RebootMachine;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Log::Log4perl;
use Permabit::Assertions qw(assertNumArgs);

use base qw(testcases::RemoteMachineBase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

###############################################################################
##
sub testReboot {
  my ($self) = assertNumArgs(1, @_);
  $self->{machine}->restart();
}

1;
