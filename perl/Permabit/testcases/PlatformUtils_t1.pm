######################################################################
# Test the Permabit::PlatformUtils module
#
# $Id$
##
package testcases::PlatformUtils_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use File::Path qw(mkpath);
use File::Temp;

use Permabit::Assertions qw(
  assertEq
  assertEqualNumeric
  assertEvalErrorMatches
  assertFalse
  assertNENumeric
  assertNumArgs
  assertRegexpMatches
  assertTrue
);
use Permabit::PlatformUtils qw(
  getClocksource
  getDistroInfo
  getReleaseInfo
  isLenny
  isLinux
  isPrecise
  isRaring
  isRedHat
  isSles
  isSqueeze
  isWheezy
  isWindows
);
use Permabit::SystemUtils qw(machineType);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

# A map from distro to sample lsb_release output from that distro.
my $LSB_RELEASE_OUTPUTS = {
  lenny   => "Distributor ID: Debian\nRelease: 5.0.10\nCodename: lenny\n",
  squeeze => "Distributor ID: Debian\nRelease: 6.0.10\nCodename: squeeze\n",
  wheezy  => "Distributor ID: Debian\nRelease: 7.1\nCodename: wheezy\n",
  precise => "Distributor ID: Ubuntu\nRelease: 12.10\nCodename: precise\n",
  raring  => "Distributor ID: Ubuntu\nRelease: 13.04\nCodename: raring\n",
  redHat  => "Distributor ID: RedHatEnterpriseServer\nRelease: 6.6\n"
             . "Codename: Santiago\n",
  sles    => "Distributor ID: SUSE LINUX\nRelease: 11\nCodename: n/a\n",
};

my $MACHINE_TYPE_OUTPUTS = {
  linux   => "Linux",
  windows => "Cygwin",
  sun     => "Unknown",
};

my $fakeDistro = "squeeze";
my $fakeOs;

######################################################################
##
sub _fakeLsbRelease {
  my ($host) = assertNumArgs(1, @_);
  return YAML::Load($LSB_RELEASE_OUTPUTS->{$fakeDistro});
}

######################################################################
##
sub fakeMachineType {
  my ($host) = assertNumArgs(1, @_);
  if (defined($fakeOs)) {
    return $MACHINE_TYPE_OUTPUTS->{$fakeOs};
  }
  return machineType($host);
}

######################################################################
##
sub set_up {
  my ($self) = @_;
  $self->SUPER::set_up();
  # Override PlatformUtils' _getLsbRelease method to facilitate testing. Keep
  # track of the original method so that they can be restored in tear_down.
  {
    no warnings;
    $self->{_getLsbRelease} = \&Permabit::PlatformUtils::_getLsbRelease;
    $self->{_machineType}   = \&Permabit::PlatformUtils::machineType;
    *Permabit::PlatformUtils::_getLsbRelease = \&_fakeLsbRelease;
    *Permabit::PlatformUtils::machineType = \&fakeMachineType;
  }
}

######################################################################
# Restore the RSVP methods so that other tests aren't effected
##
sub tear_down {
  my ($self) = @_;
  {
    no warnings;
    $fakeOs = undef;
    *Permabit::PlatformUtils::_getLsbRelease = $self->{_getLsbRelease};
    *Permabit::PlatformUtils::machineType = $self->{_machineType};
  }
  $self->SUPER::tear_down();
}


######################################################################
# Test getClocksource
##
sub testGetClocksource {
  my ($self) = assertNumArgs(1, @_);

  {
    my $dir = File::Temp->newdir('PlatformTestXXXX', DIR => '/u1');
    local $Permabit::PlatformUtils::SYSFS_ROOT = "$dir";

    eval { getClocksource() };
    assertEvalErrorMatches(qr/no such file/i);

    my $path = "$dir/devices/system/clocksource/clocksource0";
    mkpath($path);
    $log->debug("using sysfs=$path");

    open(my $clocksource, '>', "$path/current_clocksource");
    print $clocksource "";
    close($path);
    system('sync');
    eval { getClocksource() };
    assertEvalErrorMatches(qr/nothing found in/i);

    open($clocksource, '>', "$path/current_clocksource");
    print $clocksource "  \n";
    close($path);
    system('sync');
    eval { getClocksource() };
    assertEvalErrorMatches(qr/nothing found in/i);

    open($clocksource, '>', "$path/current_clocksource");
    print $clocksource "foo bar\n";
    close($path);
    system('sync');
    $self->assert_str_equals('foo bar', getClocksource());

    open($clocksource, '>', "$path/current_clocksource");
    print $clocksource "hpet\nfoo";
    close($path);
    system('sync');
    $self->assert_str_equals('hpet', getClocksource());
  }

  # Check the clocksource for real
  my $reSource = qr/acpi_pm|hpet|jiffies|kvm-clock|tsc|xen/;
  assertRegexpMatches($reSource, getClocksource());
}

######################################################################
# Test getDistroInfo and make sure it returns *something* since we 
# can't guarantee that it runs on a specific distro.
##
sub testLSBRelease {
  my ($self) = assertNumArgs(1, @_);
  assertRegexpMatches(qr/\S+/, getDistroInfo());
}

######################################################################
# Test isLinux()
##
sub testIsLinux {
  my ($self) = assertNumArgs(1, @_);

  # Failure test
  $fakeOs = 'sun';
  assertFalse(isLinux());

  # Success test
  $fakeOs = 'linux';
  assertTrue(isLinux());
}

######################################################################
# Test isWindows()
##
sub testIsWindows {
  my ($self) = assertNumArgs(1, @_);

  # Failure test
  $fakeOs = 'linux';
  assertFalse(isWindows());

  # Success test
  $fakeOs = "windows";
  assertTrue(isWindows());
}

######################################################################
# Check that a distro-checking command works only on lsb_release output for
# that distro.
#
# @param distro   The distro to check the command for
##
sub checkIsDistro {
  my ($self, $distro) = assertNumArgs(2, @_);
  my $defaultDistro = $fakeDistro;
  my $subName = "is" . ucfirst($distro);

  foreach my $testDistro (keys %{$LSB_RELEASE_OUTPUTS} ) {
    no strict 'refs';
    $fakeDistro = $testDistro;
    my $isDistro = &{$subName}();
    if ($distro eq $testDistro) {
      assertTrue($isDistro);
    } else {
      assertFalse($isDistro);
    }
  }

  $fakeDistro = $defaultDistro;
}

######################################################################
##
sub testIsDistro {
  my ($self) = assertNumArgs(1, @_);
  foreach my $distro (keys %{$LSB_RELEASE_OUTPUTS} ) {
    $self->checkIsDistro($distro);
  }
}

######################################################################
##
sub testGetReleaseInfo {
  my ($self) = assertNumArgs(1, @_);
  local @Permabit::PlatformUtils::RELEASE_MAPPINGS = (
    q(piggy    5.3  lenny   R53I0-5-3-0-0),
    q(waldorf  4.2  etch    R42I12),
    q(fozzie   3.3  sarge   R33I8),
    q(gonzo    2.0  sarge   R17I4),
    q(albireo  5.0  squeeze,lenny albireo),
  );
  local $Permabit::PlatformUtils::CODENAME = 'piggy';

  my @tests = (
    { codename       => 'waldorf',
      version        => '4.2',
      suites         => ['etch'],
      defaultRelease => 'etch',
      relTag         => 'R42I12',
    },
    { codename       => 'fozzie',
      version        => '3.3',
      suites         => ['sarge'],
      defaultRelease => 'sarge',
      relTag         => 'R33I8',
    },
    { codename       => 'gonzo',
      version        => '2.0',
      suites         => ['sarge'],
      defaultRelease => 'sarge',
      relTag         => 'R17I4',
    },
    { codename       => 'albireo',
      version        => '5.0',
      suites         => ['squeeze','lenny'],
      defaultRelease => 'squeeze',
      relTag         => 'albireo',
    });
  foreach my $expected (@tests) {
    my $codename = delete $expected->{codename};
    $self->assert_deep_equals($expected, getReleaseInfo($codename));
  }

  # Non-existant
  eval { getReleaseInfo('waldo') };
  assertEvalErrorMatches(qr/Found wrong number of results/,
                         "Wait... where's Waldo?!");

  # Too many results, due to an additional fozzie
  push(@Permabit::PlatformUtils::RELEASE_MAPPINGS,
       q(fozzie   3.3  sarge   R33I9));
  eval { getReleaseInfo('fozzie') };
  assertEvalErrorMatches(qr/Found wrong number of results/,
                         "There should be duplicate fozzies");

  # Test default behavior with no args
  $self->assert_str_equals('R53I0-5-3-0-0', getReleaseInfo()->{relTag});
}

1;
