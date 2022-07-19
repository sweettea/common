##
# Make sure we can identify the test storage device on this machine.
#
# N.B.: Make sure this stays in sync with the code in
# Permabit::LabUtils::getTestBlockDeviceNames!
#
# $Id$
##
package CheckServer::Test::StorageDevice;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use base qw(CheckServer::AsyncTest);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my @TEST_DEVICES = qw(/dev/vdo_scratch
                      /dev/vdo_scratchdev_*
                      /dev/md0
                      /dev/xvda2
                      /dev/sda8
                    );

########################################################################
# @inherit
##
sub skip {
  my ($self) = assertNumArgs(1, @_);
  return (!$self->isJFarm()
          && !$self->isPFarm()
          && !$self->isVFarm()
          && !$self->isAlbPerf());
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  foreach my $device (@TEST_DEVICES) {
    if (-b $device) {
      return;
    }
  }

  # no fix available
  $self->fail("unable to locate test storage device");
}

1;

