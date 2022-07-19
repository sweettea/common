##
# Implementation of SystemUtils Configured-dependent methods.
#
# @synopsis
#
#     use Permabit::SystemUtils::Implementation;
#
#     our $IMPLEMENTATION = Permabit::SystemUtils::Implementation->new();
#
# @description
#
# This class should only be instantiated by the Permabit::SystemUtils
# module. Alternate implementations should derive from it and be
# Configured for instantiation.
##

package Permabit::SystemUtils::Implementation;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Log::Log4perl;
use Permabit::Assertions qw(assertNumArgs);

use base qw(Permabit::Configured);

# Log4perl Logging object
my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
# Consider all hosts as not cloud machines.
#
# @param host   The name of the host in question
#
# @return   False
##
sub mightBeCloudMachine {
  my ($self, $host) = assertNumArgs(2, @_);
  return 0;
}

######################################################################
# There are no virtual machines (based on the definition of such in
# SystemUtils view).
#
# @param host      Hostname of the virtual machine
# @param command   The command to send
##
sub runVirtualMachineCommand {
  my ($self, $host, $command) = assertNumArgs(3, @_);
  $log->warn("Cannot issue virtual command $command to $host");
}

1;
