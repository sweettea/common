##
# Check that the machine has no unexpected logical volumes.
#
# Note: The following excludes the value volume groups and drives that
#       are being used on the afarm instances.
#
#       vg_xvda2
#       vg_xvde2
#       scratch
#
# Note: Also excluded are any /dev/xvd[a-z]\d* devices that contain LVM physcal
#       volumes, since we need it to provide a large enough /u1 for testing.
#       With the AWS infrastructure, we can't guarantee that we will always
#       have a specific block device name to exclude.  (Tests should use
#       /dev/vdo_scratch anyway)
#
#
# $Id$
##
package CheckServer::Test::LVM;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);

  # Start by checking to make sure we can run vgscan and that it isn't in a
  # state that would cause things to hang.
  my $timeout = 30;
  my @outputLines;
  eval {
    local $SIG{ALRM} = sub { die "alarm\n" };
    alarm $timeout;
    @outputLines = $self->assertCommand('vgscan 2>&1');
    alarm 0;
  };
  if ($EVAL_ERROR) {
    if ($EVAL_ERROR eq "alarm\n") {
      $self->fail("vgscan failed to return in $timeout seconds.");
    } else {
      $self->fail("Unable to run vgscan: $EVAL_ERROR.");
    }

    return;
  }

  # Any devices matching the scratch pattern are part of the permanent
  # configuration.
  my $vgPattern = $self->getScratchVGPattern();
  if ($self->isRedHat()) {
    $self->checkRHELLike($vgPattern);
  } else {
    $self->checkNotRHELLike($vgPattern);
  }

  # Get a list of volume groups for removal in case any are left after the
  # initial pass of lvm fixes.
  my $vgCommand = "vgs --noheadings -o vg_name";
  foreach my $vg (grep({
                         $_ !~ /^$vgPattern/;
                       } map {
                         chomp;
                         s/^\s*|\s*$//g;
                         $_;
                       } $self->assertCommand($vgCommand))) {
    $self->fail("found LVM volume group $vg");
    $self->addFixes("vgs $vg && vgremove --force $vg");
  }

  # Get a list of physical volumes for removal in case any are left after the
  # initial pass of lvm fixes.
  my $pvCommand = "pvs --noheadings -o pv_name,vg_name";
  foreach my $line (map({
                       chomp($_);
                       $_;
                      } $self->assertCommand($pvCommand))) {
    my ($pv, $vg) = split(" ", $line);
    if (!$vg || ($vg =~ /^$vgPattern$/)) {
      next;
    }

    $self->fail("found LVM physical volume $pv");
    $self->addFixes("pvremove -f $pv $vg && vgscan");
  }

  # Check for warnings of orphaned physical volumes since their existence
  # breaks the 'does a volume already exist?' check in VDO manager (VDO-4361).
  if (grep({
            $_ =~ /WARNING: .* not found or rejected by a filter/
           } $self->assertCommand("pvs 2>&1"))) {
    $self->fail("found orphaned physical volume");
    $self->addFixes("pvscan --cache");
  }
}

########################################################################
# Check LVM config on a RHEL-like host (RHEL, Centos, Fedora).
#
# @param vgPattern  The pattern for identifying devices which are allowed
##
sub checkRHELLike {
  my ($self, $vgPattern) = assertNumArgs(2, @_);

  # Get the tree of block devices with name and type, forced to ASCII
  # representation.
  my $lsblkCommand = 'env LANG=C lsblk -noheadings -o NAME,TYPE';
  foreach my $line ($self->assertCommand($lsblkCommand)) {
    if ($line =~ /^\s*([`|-]-)*(?<name>([\w.-])+)\s+(?<type>\w+)$/) {
      my ($name, $type) = ($+{name}, type => $+{type});
      if ($name =~ /$vgPattern/) {
        $log->debug("Scratch device '$name' ignored");
        next;
      }

      if ($type eq "lvm") {
        my $command = "dmsetup splitname --noheadings $name";
        my ($vg, $lv) = split(/:/, $self->assertCommand($command));

        # Remove the lv, and if it's the last lv, remove the vg too
        $self->fail("Found LVM logical volume $lv");
        $self->addFixes("lvremove --force $vg/$lv");
        my $removeIfLast
          = join('; ',
                 "lv_count=`vgs -o lv_count --noheadings $vg`",
                 "[ \"\$lv_count\" != 0 ] || vgremove --force $vg");
        $self->addFixes($removeIfLast);
        next;
      }

      if (($type ne "dm") && ($type ne "vdo")) {
        next;
      }

      $self->fail("Found device mapper target $name");
      $self->fixVolume($name);
    }
  }
}

########################################################################
# Check LVM config on a host which is not RHEL-like (i.e. not RHEL, Centos, or
# Fedora).
#
# @param vgPattern  The pattern for identifying devices which are allowed
##
sub checkNotRHELLike {
  my ($self, $vgPattern) = assertNumArgs(2, @_);
  my $command = "dmsetup ls 2>&1 | awk '!/No devices/ {print \$1}'";
  foreach my $volume (map({
                           chomp($_);
                          } grep {
                            !/^$vgPattern/;
                          } $self->assertCommand($command))) {
    my $dmstatus = $self->assertCommand("dmsetup status $volume");
    # Ignore logical mappings used by multipath
    if ($dmstatus =~ m/^\d+\s+\d+\s+multipath/) {
      next;
    }

    # "dmsetup remove -f" (at least on squeeze) starts by swapping out the dm
    # table entries for new ones using target "error".  Unfortunately this
    # triggers udev which runs blkid to try to identify the content of the
    # device, resulting in logged errors from the read attempts, which can
    # cause some confusion. So try a less forceful cleanup (which tries the
    # remove but not the swap to "error") first.
    $self->fail("found LVM volume $volume");
    $self->fixVolume($volume);
  }
}

########################################################################
# Add a fix to remove a volume.
#
# @param volume  The volume to remove
##
sub fixVolume {
  my ($self, $volume) = assertNumArgs(2, @_);
  $self->addFixes("dmsetup remove $volume || dmsetup remove -f $volume");
}

1;
