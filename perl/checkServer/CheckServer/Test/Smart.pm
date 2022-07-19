##
# Checks to see if SMART is enabled for the drives examined by
# Permabit::RemoteMachine::waitForDiskSelfTests.
#
# $Id$
##
package CheckServer::Test::Smart;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my @SMART_OK_RES = (
  qr/Device supports SMART and is Enabled/,
  qr/SMART support is:\s+Enabled/,
  qr/Device does not support SMART/,
  qr/SMART support is:\s+Unavailable - device lacks SMART capability./);

########################################################################
# @inherit
##
sub skip {
  my ($self) = assertNumArgs(1, @_);
  return $self->isVirtual();
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my $okRE = '(' . join(')|(', @SMART_OK_RES) . ')';
  my @devices
    = ($self->assertCommand('cat /proc/partitions') =~ / ([hs]d[a-z])$/mg);

  foreach my $dev (@devices) {
    my $smartOut = $self->assertCommand("smartctl -i /dev/$dev");
    if ($smartOut =~ /$okRE/) {
      next;
    }

    if ($smartOut =~ /SMART support is:\s+Disabled/) {
      $self->fail("SMART support is: Disabled on /dev/$dev");
      $self->addFixes("smartctl -s on /dev/$dev");
      next;
    }

    $self->fail("Nonsense output from smartctl on /dev/$dev");
  }
}


1;

