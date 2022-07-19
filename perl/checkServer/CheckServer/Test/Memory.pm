##
# Check that the machine has at least the minimal amount of memory, and check
# that active memory and boot settings are unrestricted or set to 6GB.
# TODO: Add the --zipl argument to the grubby command where appropriate.
#
# $Id$
##
package CheckServer::Test::Memory;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use CheckServer::Constants;

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  $self->checkMemory();
  $self->checkLimitedMemory();

  my $setMemory = $self->getMemorySetting();
  if ($setMemory && (lc($setMemory) ne "7168m")) {
    $self->addFixes("grubby --update-kernel ALL --remove-args mem");
    $self->fail("kernel command line should have no memory restrictions"
                . " or a setting of 7168M (6GB)");
    $self->suggestReboot();
  }
}

######################################################################
# Check the amount of physical memory.
##
sub checkMemory {
  my ($self) = assertNumArgs(1, @_);
  my $size = $self->getMemory();
  if ($size < $MIN_MEMORY) {
    $self->fail("All machines are expected to have at least $MIN_MEMORY kB"
                . ", actual: $size kB");
  }
}

######################################################################
# Check if the memory was limited at boot time and if so to the correct value.
##
sub checkLimitedMemory {
  my ($self) = assertNumArgs(1, @_);
  my $cmdline = $self->readFileOrAbort('/proc/cmdline');
  if (($cmdline =~ m/mem=(\d+\w)/) && (lc($1) ne '7168m')) {
    $self->fail("Current memory value is limited and not 7168M (6GB)");
  }
}

######################################################################
# Get the amount of memory configured
#
# @return value of memory limit set in the config file, or undef if not set
##
sub getMemorySetting {
  my ($self) = assertNumArgs(1, @_);
  my $conf = `grubby --info DEFAULT`;
  my $re = 'args="([^"]*)"';
  if ($conf =~ /$re/m) {
    my $args = $1;
    if ($args =~ /mem=(\S+)/) {
      return $1;
    }
  }
  return undef;
}


1;
