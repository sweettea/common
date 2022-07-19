##
# Check that there are no unexpected mounts.
#
# $Id$
##
package CheckServer::Test::NFSMounts;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(
  assertMinArgs
  assertNumArgs
);

use Permabit::Utils qw(hostToIP);

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub skip {
  my ($self) = assertNumArgs(1, @_);
  # XXX: Different VM environments have different mount points. We should
  #      figure out a way to check them. Perhaps updating perl.yaml at
  #      provisioning time.
  return ($self->isAnsible() && !$self->isPFarm());
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my $server = $self->getParameter('nfsServer');
  my $ip     = (defined($server) ? hostToIP($server) : undef);
  my %expected = %{$self->getParameter('permabitMounts', {})};

  foreach my $mounted ($self->assertCommand('mount')) {
    if ($mounted !~ m|^[^:]+:(\S+) on (\S+) .*,addr=([0-9.]+)|) {
      next;
    }

    my ($share, $point, $addr) = ($1, $2, $3);
    my $expectedShare = delete $expected{$point};
    if (!defined($expectedShare)) {
      next;
    }

    if ($expectedShare ne $share) {
      $self->fail("$point mounted from $share, not $expectedShare");
    }

    if (defined($ip) && ($ip ne $addr)) {
      $self->fail("$share mounted from $addr, not $ip");
    }
  }

  foreach my $share (keys(%expected)) {
    $self->fail("$share not mounted");
  }
}

1;
