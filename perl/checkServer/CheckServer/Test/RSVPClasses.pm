##
# Check the RSVP class membership.
#
# $Id$
##
package CheckServer::Test::RSVPClasses;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);
use Permabit::PlatformUtils qw(getPkgBundle);
use Permabit::Triage::TestInfo qw(:albireo);

use CheckServer::Constants;

use base qw(CheckServer::AsyncTest);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

# A map from RSVP class names to methods used to check whether a host should
# be in that class
my %CLASS_MAP = (
  'ALBIREO-PMI'  => 'isAlbPerf',
  FARM           => 'isFarm',
  FEDORA         => 'isFedora',
  JFARM          => 'isJFarm',
  'LINUX-UDS'    => [qw(isCentOS8 isFedora isOotpa isPlow)],
  'LINUX-VDO'    => [qw(isCentOS8 isFedora isOotpa isPlow)],
  PFARM          => 'isPFarm',
  'VDO-PMI'      => 'isVDOPerf',
  # vfarm, afarm, and lfarms should all report themselves as VFARM
  VFARM          => [qw(isVFarm isDevVM)],
);

my %VERSION_MAP = (
  # The centos8 check would normally be isOotpa but CentOS 8 does not
  # identify itself as Ootpa (though it is) so we use the check for CentOS 8
  # instead.
  CENTOS8   => 'isCentOS8',
  RHEL6     => 'isSantiago',
  RHEL7     => 'isMaipo',
  RHEL8     => 'isOotpa',
  RHEL9     => 'isPlow',
  FEDORA27  => 'isTwentySeven',
  FEDORA28  => 'isTwentyEight',
  FEDORA29  => 'isTwentyNine',
  FEDORA30  => 'isThirty',
  FEDORA31  => 'isThirtyOne',
  FEDORA32  => 'isThirtyTwo',
  FEDORA33  => 'isThirtyThree',
  FEDORA34  => 'isThirtyFour',
  FEDORA35  => 'isThirtyFive',
  FEDORA36  => 'isThirtySix',
  RAWHIDE   => 'isRawhide',
);

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  # No classes or in MAINTENANCE skips everything else
  # XXX Why would something have no classes?
  if (!$self->hasRSVPClasses() || $self->inRSVPClass('MAINTENANCE')) {
    return;
  }

  # Everything should always be in ALL and VDO
  $self->assertMember('ALL');
  $self->assertMember('VDO');

  my $perf = 0;
  while (my ($key, $value) = each(%CLASS_MAP)) {
    my $should = 0;
    foreach my $check ((ref($value) eq 'ARRAY') ? @{$value} : $value) {
      no strict;
      if ($self->$check()) {
        $should = 1;
        if (($key eq 'ALBIREO-PMI') || ($key eq 'VDO-PMI')) {
          $perf = 1;
        }
        last;
      }
    }

    ($should ? $self->assertMember($key) : $self->assertNotMember($key));
  }

  my @osClasses = ();
  while (my ($key, $check) = each(%VERSION_MAP)) {
    no strict;
    if ($self->$check()) {
      $self->assertMember($key);
      push(@osClasses, $key);
    } else {
      $self->assertNotMember($key);
    }
  }

  if (scalar(@osClasses) == 0) {
    $self->fail("Not a memeber of an OS class");
  } elsif (scalar(@osClasses) > 1) {
    $self->fail("Is a member of multiple OS classes: @osClasses");
  }

  if ($perf) {
    return;
  }

  my $release = uc(getPkgBundle());
  # XXX not all of these are really OS classes so take out the
  #     real OS classes for now since we deal with them in
  #     _assertMemberOsClass(). Eventually, we'll want something
  #     that asserts a machine is a member of a configuration:
  #       ALBIREO, VDO, EA, PMI, etc
  #     and a member of an OS:
  #       SQUEEZE, RHEL6, RIZZO, etc
  my %distFilter = map { ($_, 1) } @DIST_CLASSES;
  foreach my $class (grep({ !exists($distFilter{$_}) }
                          Permabit::RSVP::listOsClasses())) {
    (($class eq $release)
     ? $self->assertMember($class)
     : $self->assertNotMember($class));
  }
}

######################################################################
# Assert that the host should be a member of an RSVP class.
#
# @param class  the name of the class
##
sub assertMember {
  my ($self, $class) = @_;
  if (!$self->inRSVPClass($class)) {
    $self->fail("Should be a member of class $class");
    my $name = $self->shortHostname();
    $self->addFixes("rsvpclient modify $name --add $class");
  }
}

######################################################################
# Assert that the host should be a member of an RSVP class.
#
# @param class  the name of the class
##
sub assertNotMember {
  my ($self, $class) = @_;
  if ($self->inRSVPClass($class)) {
    $self->fail("Should not be a member of class $class");
    my $name = $self->shortHostname();
    $self->addFixes("rsvpclient modify $name --del $class");
  }
}

1;

