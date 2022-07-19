##
# Check that /u1 isn't too full and that it is at least the correct
#   size for the server that it is on.
# In the event that it is too full under --fix: removes files older
#   than 7 days and then delete empty directories.
# In the event that the /u1 directory is too small under --fix: issues
#   a mount -a command which should generally resolve the problem if
#   the system is properly configured.
#
# $Id$
##
package CheckServer::Test::U1;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);
use Permabit::Constants;

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  # First, resolve the device that /u1 resides on
  my $device = $self->getPartitionDevice("/u1");
  if (!defined($device)) {
    $self->fail("Unable to find partition containing /u1");
    return;
  }

  # First, check to make sure /u1 has the proper disk size
  eval {
    if ($self->getPartitionSize($device) < $DEFAULT_U1_SIZE) {
      $self->fail("/u1 is too small, $DEFAULT_U1_SIZE or more expected.");
      $self->addFixes("mount -a");
    }
  };
  if ($EVAL_ERROR) {
    $self->fail($EVAL_ERROR);
  }

  # Next, check to make sure it is not too full
  my $limit = $U1_LIMIT;
  if ($self->isFarm()) {
    $limit = ($self->isVirtual() ? $VFARM_U1_LIMIT : $FARM_U1_LIMIT);
  }

  eval {
    my $available = $self->getPartitionAvailableSize("/u1");
    if ($available >= $limit) {
      return;
    }

    $self->fail("/u1 too full ($available < $limit)");
    $self->addFixes('find /u1 -mtime +7 -type f -print | xargs rm -f',
                    'find /u1 -depth -type d -print '
                    . '| xargs rmdir 2>/dev/null');
  };
  if ($EVAL_ERROR) {
    $self->fail($EVAL_ERROR);
  }
}

1;
