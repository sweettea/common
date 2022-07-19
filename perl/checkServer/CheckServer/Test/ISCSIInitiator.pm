##
# Check for ISCSI initiators set up by Permabit::BlockDevice::ISCSI.
#
# $Id$
##
package CheckServer::Test::ISCSIInitiator;

use Permabit::Assertions qw(assertNumArgs);

use base qw(CheckServer::Test);

########################################################################
# @inherit
##
sub skip {
  my ($self) = assertNumArgs(1, @_);
  return ($self->isLenny() || $self->isSqueeze());
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my @mounts = ();
  foreach my $mount (`sudo iscsiadm -m session 2>/dev/null`) {
    if ($mount =~ /(iqn.2017-07.com.permabit.block-device\S+)/) {
      push(@mounts, $1);
    }
  }

  if (@mounts) {
    $self->fail(join("\n  ", 'Found left-over ISCSI mounts:', @mounts));
    $self->addFixes(map({ $_ = "iscsiadm -m node -T $_ -u" } @mounts));
  }

  my @portals = ();
  foreach my $portal (`sudo iscsiadm -m node 2>/dev/null`) {
    if ($portal =~ /^(\S+),\d+ iqn.2017-07.com.permabit.block-device\S+/) {
      push(@portals, $1);
    }
  }

  if (@portals) {
    $self->fail(join("\n  ",
                     'Found left-over ISCSI discovery targets:',
                     @portals));
    $self->addFixes(map({ $_ = "sudo iscsiadm -m node -o delete -p $_" }
                        @portals));
  }
}

1;

