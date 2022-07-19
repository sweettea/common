##
# Check for ISCSI targets set up by Permabit::BlockDevice::ISCSI.
#
# $Id$
##
package CheckServer::Test::ISCSITarget;

use Permabit::Assertions qw(assertNumArgs);

use base qw(CheckServer::Test);

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my @targets = ();
  foreach my $line ($self->runCommand('targetcli /iscsi ls')) {
    if ($line =~ /Targets: 0\]/) {
      last;
    }

    if ($line =~ /^  o- (iqn\S+)/) {
      my $target = $1;
      push(@targets, $target);
      $self->addFixes("targetcli /iscsi delete $target");
    }
  }

  my $report;
  if (@targets) {
    $report = join("\n  ", "found iscsi targets:", @targets);
  }

  my @backstores = ();
  foreach my $line ($self->runCommand('targetcli /backstores/block ls')) {
    if ($line =~ /Storage Objects: 0\]/) {
      if ($report) {
        $self->fail($report);
      }

      return;
    }

    if ($line =~ /^  o- (\S+)/) {
      my $backstore = $1;
      push(@backstores, $backstore);
      $self->addFixes("targetcli /backstores/block delete $backstore");
    }
  }

  $report = (defined($report)
             ? "$report\nwith backstores:" : "found iscsi backstores:");
  $self->fail(join("\n  ", $report, @backstores));
}

1;

