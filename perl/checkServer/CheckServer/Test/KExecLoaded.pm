##
# Check that kexec is loaded.
#
# $Id$
##
package CheckServer::Test::KExecLoaded;

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
  # XXX: We don't have a functional kdump configuration on PERF hosts.
  return (($self->machine() eq 's390x') || (getScamVar('PERF') eq 'yes'));
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  if (grep(/1/, $self->readFileOrAbort('/sys/kernel/kexec_crash_loaded'))) {
    return;
  }

  $self->fail("kexec not loaded, KDump not configured properly.");
  $self->suggestReboot();
}

1;

