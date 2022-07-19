##
# Check that we have a crashkernel= value in the kernel commandline
#
# $Id$
##
package CheckServer::Test::KDumpConfig;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);
use Permabit::Utils qw(getScamVar);

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub skip {
  my ($self) = assertNumArgs(1, @_);
  # XXX: We don't have a functional kdump configuration on PERF hosts
  return (($self->machine() eq 's390x') || (getScamVar('PERF') eq 'yes'));
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my $crashParam;
  my $fixStr;
  my $grepString;
  my $grubConfig;
  my $grub2DefaultStart = 'GRUB_CMDLINE_LINUX_DEFAULT';

  # Set the expected crashkernel values based on distro
  if ($self->isSantiago()) {
    $crashParam = 'crashkernel=128M';
  } elsif ($self->isMaipo() || ($self->isOotpa() || $self->isCentOS8())) {
    $crashParam = 'crashkernel=auto';
    $grub2DefaultStart = 'GRUB_CMDLINE_LINUX';
  } else {
    # If we didn't set crashParam, then we probably don't have kdump
    # configured for the given distro.  So we should just return for now.
    return;
  }

  # Detect grub version and assemble the checks as necessary
  my $grubVersion = $self->getGrubVersion();
  my $sedCmd = "sed -r -i";
  if ($grubVersion == 1) {
    $grubConfig = "/boot/grub/menu.lst";
    $grepString = "^\\s*(kernel|linux).*$crashParam.*";
    $fixStr = "$sedCmd 's/^((linux|kernel).*)/\\1 $crashParam/' $grubConfig";
  } elsif ($grubVersion == 2) {
    $grubConfig = "/etc/default/grub";
    $grepString = "$grub2DefaultStart=\".*$crashParam.*\"";
    $fixStr = "$sedCmd 's/$grub2DefaultStart\".*\"/"
                       . "$grub2DefaultStart\"$crashParam\"/\' "
                       . $grubConfig;
  } else {
    # We don't know what we're running.  So we probably don't have kdump
    # configured in the first place.
    return;
  }

  # Read grub config and check to see if it is valid
  if (grep(/$grepString/, $self->readFileOrAbort($grubConfig))) {
    return;
  }

  $self->fail("$crashParam not found in grub config.");
  $self->addFixes($fixStr);
  $self->suggestReboot();
}

1;

