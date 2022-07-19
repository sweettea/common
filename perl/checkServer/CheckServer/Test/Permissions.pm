##
# Check file and directory permissions.
#
# $Id$
##
package CheckServer::Test::Permissions;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use File::stat;
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
  foreach my $dir (@CHECKED_DIRS) {
    $self->checkStaffPermissions($dir);
  }

  if (!$self->isFedora()) {
    $self->checkRootWritePermissions("/sys/permatest/printk");
  }

  my $file = "/u1/zubenelgenubi";
  if (-f $file) {
    $self->checkStaffPermissions($file);
  }

  foreach my $g (@TEST_DIRS) {
    foreach my $dir (glob($g)) {
      my $stat = stat($dir) || $self->fail("no such dir $dir");
      if ($stat->uid == 0) {
        my ($realOwner) = ($dir =~ m|/[[:alpha:]]+-(\w+)/?|);
        if ($realOwner eq 'root') {
          $self->fail("$dir not allowed to exist");
          $self->addFixes("rm -rf $dir");
        } else {
          $self->fail("$dir is owned by root");
          $self->addFixes("chown $realOwner:staff $dir");
        }
      }
    }
  }
}

######################################################################
# Check whether the given file or directory is both readable and writeable
# by members of $STAFF_GID.
#
# @param file  The file or directory to check
##
sub checkStaffPermissions {
  my ($self, $file) = assertNumArgs(2, @_);
  my $stat          = stat($file) || _die("no such file $file");
  my $modeStr       = sprintf "%lo", $stat->mode;
  if ($stat->gid == $STAFF_GID) {
    # If group == staff, the file must be group accessible.
    if (($stat->mode & 0060) != 0060) {
      $self->fail("$file is not group accessible ($modeStr, "
                  . $stat->mode . ")");
      $self->addFixes("chmod g+rw $file");
    }
  } elsif (($stat->mode & 0006) != 0006) {
    # Otherwise, the file must be world accessible.
    $self->fail("$file is not world accessible ($modeStr, "
                . $stat->mode . ")");
    $self->addFixes("chmod a+rw $file");
  }
}

######################################################################
# Check whether the given file or directory is both readable and writeable
# by nightly.
#
# @param file  The file or directory to check
##
sub checkNightlyPermissions {
  my ($self, $file) = assertNumArgs(2, @_);
  if ($file =~ /logfile.timestamp$/) {
    # Ignore files that are always manipulated as root
    return;
  }

  my $stat    = stat($file) || $self->fail("no such file $file");
  my $modeStr = sprintf "%lo", $stat->mode;
  if (($stat->uid != $NIGHTLY_UID) || !($stat->mode & 0600)) {
    # files must be accessible by nightly
    $self->fail("$file is not nightly accessible ($modeStr)");
    $self->addFixes("chown nightly $file && chmod o+rw $file");
  }
}

######################################################################
# Check whether the given file or directory exists, is owned by root,
# and has write permissions.
#
# @param file  The file or directory to check
##
sub checkRootWritePermissions {
  my ($self, $file) = assertNumArgs(2, @_);
  my $stat = stat($file);
  if (defined($stat)) {
    if ($stat->uid != 0) {
      my $user = (getpwuid($stat->uid))[0];
      $self->fail("$file is owned by $user, not root");
    }
    if (($stat->mode & 0200) == 0) {
      $self->fail(sprintf("$file is not writable by owner (mode %lo)",
                          $stat->mode));
    }
  } else {
    $self->fail("$file does not exist");
    $self->suggestReboot();
  }
}

1;

