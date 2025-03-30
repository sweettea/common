##
# Utlity functions for probing the operating system type and version
#
# @synopsis
#
#     use Permabit::PlatformUtils;
#
#     isLinux()
#     isStatler()
#     isWaldorf()
#     isWindows()
#
#     All return true or false.
#
# @description
#
# C<Permabit::PlatformUtils> provides methods for determining the
# operating system of the local machine and, if running on Debian Linux,
# determining which release.
#
# $Id$
##
package Permabit::PlatformUtils;

use strict;
use warnings FATAL => qw(all);
use autodie qw(open close);

use Carp qw(croak);
use English qw(-no_match_vars);
use Log::Log4perl;
use Permabit::Assertions qw(
  assertMinMaxArgs
  assertNumArgs
  assertTrue
);
use Permabit::Constants;
use Permabit::SystemUtils qw(
  assertCommand
  assertQuietCommand
  getScamVar
  machineType
  runCommand
);
use YAML;

use base qw(Exporter);

our @EXPORT_OK = qw(
  getClocksource
  getDistroInfo
  getPkgBundle
  getReleaseInfo
  isAlbireo
  isCentOS
  isCentOS8
  isCoughlan
  isDebian
  isDebianBased
  isFedora
  isFedoraNext
  isJessie
  isLenny
  isLinux
  isMaipo
  isOotpa
  isPlow
  isPrecise
  isPreLenny
  isRaring
  isRawhide
  isRedHat
  isSantiago
  isSles
  isSles11SP2
  isSles11SP3
  isSqueeze
  isStatler
  isUbuntu
  isVivid
  isWheezy
  isWindows
  isXen
  isXenial
  isTwentySeven
  isTwentyEight
  isTwentyNine
  isThirty
  isThirtyOne
  isThirtyTwo
  isThirtyThree
  isThirtyFour
  isThirtyFive
  isThirtySix
  isThirtySeven
  isThirtyEight
  isThirtyNine
  isForty
  isFortyOne
);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

our $CUR_REL_FILE           = '/etc/permabit/current_release';
our $SLES_VER_FILE          = '/etc/SuSE-release';
our $LENNY_DEBIAN_VERSION   = 5.0;
our $SLES11SP2_VERSION      = 11.2;
our $SLES11SP3_VERSION      = 11.3;
our $SYSFS_ROOT             = '/sys';

our $SLES_VERSION;
my  $INSTALLED_RELEASE;

# Cache for "lsb_release" output from localhost, which is queried many
# times in the checkServer script.
my $localLSBReleaseInfo;

##########################################################################
# Determines the current clocksource that the kernel is using.
#
# @return a string identifying the current clocksource.
#
# @croaks if the clocksource can't be determined.
##
sub getClocksource {
  my $file = "$SYSFS_ROOT/devices/system/clocksource/"
               . "clocksource0/current_clocksource";
  open(my $fh, '<', $file);
  my ($clockSource) = <$fh>;
  assertTrue(defined($clockSource) && scalar($clockSource !~ /^\s*$/),
             "nothing found in $file");
  chomp($clockSource);
  $log->debug("clocksource = '$clockSource'");
  return $clockSource;
}

#############################################################################
# Check a particular property of a file on a remote host using the command
# <tt>test</tt>.  For example, to check if a particular file is writable:
#
# <pre>
#   if (checkRemoteFileProperty($host, $file, "-w")) {
#     print "it's writable";
#   }
# </pre>
#
# @param host        The remote host
# @param file        The full path to the file
# @param prop        The property to check
#
# @return            true if the check returned true, false otherwise
##
sub checkRemoteFileProperty {
  my ($host, $file, $prop) = assertNumArgs(3, @_);

  my $cmd = "test " . $prop . " \"" . $file . "\"";

  # cant use assertCommand -- we expect retVal to be nonzero for false
  my $result = runCommand($host, $cmd);
  return ($result->{returnValue} == 0);
}

#############################################################################
# Determines if a host is running a Debian-based distribution.
#
# @param host       The name of the host to check
#
# @return           true if the host is running Debian or Ubuntu
##
sub isDebianBased {
  my ($host) = assertMinMaxArgs(['localhost'], 0, 1, @_);
  return isLinux($host)
         && checkRemoteFileProperty($host, "/etc/debian_version", '-e');
}

#############################################################################
# Get the lsb_release information from a given machine.
#
# @param  host       The name of the host to check
#
# @return  a hash containing lsb_release parsed as YAML.
##
sub _getLsbRelease {
  my ($host) = assertNumArgs(1, @_);
  my $stdout;
  if ($host eq 'localhost' && defined($localLSBReleaseInfo)) {
    # Cached for fast access in "checkServer".
    $stdout = $localLSBReleaseInfo;
  } else {
    $stdout = assertQuietCommand($host, 'lsb_release -irc')->{stdout};
    $stdout =~ tr/\t/ /;
    if ($host eq 'localhost') {
      $localLSBReleaseInfo = $stdout;
    }
  }
  return YAML::Load($stdout);
}

#############################################################################
# Determines whether the provided lsb_release output matches a given
# distro name pattern and release.
#
# @param  lsbRelease  Output from lsb_release, as a hash.
# @param  distro      The distro regexp to check against
# @oparam release     The release of the distro to check against
#
# @return  true if lsbRelease is of the distro (and release, if given).
##
sub _lsbReleaseMatches {
  my ($lsbRelease, $distro, $release) = assertMinMaxArgs([undef], 2, 3, @_);
  if ($lsbRelease->{"Distributor ID"} !~ /^$distro$/) {
    return 0;
  }
  return (!defined($release) || ($release eq $lsbRelease->{Codename}));
}

#############################################################################
# Determines whether a machine matches a given distribution (and, optionally,
# release thereof).
#
# @param  host       The name of the host to check
# @param  distro     The distro to check against
# @oparam release    The release of the distro to check against
#
# @return  true if the host is of the distro (and release, if given).
##
sub _isRelease {
  my ($host, $distro, $release) = assertMinMaxArgs([undef], 2, 3, @_);
  my $lsb = _getLsbRelease($host);
  return _lsbReleaseMatches($lsb, $distro, $release);
}

######################################################################
# Check if a machine is a Xen virtual machine
#
# @param host   The host
##
sub isXen {
  my ($host) = assertNumArgs(1, @_);
  return checkRemoteFileProperty($host, '/proc/xen', '-d');
}

##########################################################################
# Fetches the distribution major number.
#
# @param host      The name of the host to check
#
# @return          The major number
#
# @croaks when distribution major cannot be found or lsb_release failure
##
sub _getDistributionMajor {
  my ($host) = assertMinMaxArgs(['localhost'], 0, 1, @_);

  my $version;
  if (isSles($host)) {
    $version = _getSlesVersion();
  } else {
    $version = _getLsbReleaseMajorVersion(_getLsbRelease($host));
  }
  if ($version =~ m/^(\d+)/) {
    return $1;
  }
  croak("did not find major number on $host");
}

##########################################################################
# Returns the version major number from lsb_release results.
#
# @param   lsbRelease  Output from lsb_release, as a hash.
#
# @return  the version major number
#
# @croaks when distribution major cannot be found
##
sub _getLsbReleaseMajorVersion {
  my ($lsbRelease) = assertNumArgs(1, @_);
  if ($lsbRelease->{Release} =~ m/^(\d+)/) {
    return $1;
  }
  croak("did not find major number");
}

##########################################################################
# Fetches the distro class.
#
# @param host      The name of the host to check
#
# @return          The RSVP OS class
#
# @croaks when lsb_release does not exit properly
##
sub getDistroInfo {
  my ($host) = assertMinMaxArgs(['localhost'], 0, 1, @_);
  my $lsb = _getLsbRelease($host);
  if (_lsbReleaseMatches($lsb, "CentOS")) {
    my $major = _getLsbReleaseMajorVersion($lsb);
    if ($major == 8) {
      return "CENTOS$major";
    }
  } elsif (_lsbReleaseMatches($lsb, "Debian")) {
    my $rel = uc($lsb->{Codename});
    if (grep { $rel eq $_ } ("JESSIE", "LENNY", "SQUEEZE")) {
      return $rel;
    }
    if ($rel eq "WHEEZY") {
      assertCommand($host, "uname -r")->{stdout} =~ m/^([0-9]+)\.([0-9]+)/;
      return "WHEEZY$1$2";
    }
  } elsif (_lsbReleaseMatches($lsb, "Ubuntu")) {
    my $rel = uc($lsb->{Codename});
    if ($rel eq "VIVID") {
      return "VIVID";
    }
    if ($rel eq "XENIAL") {
      return "XENIAL";
    }
  } elsif (_lsbReleaseMatches($lsb, "RedHatEnterprise.*")) {
    my $major = _getLsbReleaseMajorVersion($lsb);
    if (($major == 6) || ($major == 7) || ($major == 8) || ($major == 9)
	|| ($major == 10)) {
      return "RHEL$major";
    }
  } elsif (_lsbReleaseMatches($lsb, "Fedora")) {
    my $rel = uc($lsb->{Codename});
    if (assertCommand($host, "uname -r")->{stdout} =~ m/.*next*.fc*.x86_64/) {
      return "FEDORANEXT";
    }
    if ($rel eq "RAWHIDE") {
      return "RAWHIDE";
    }
    my $major = _getLsbReleaseMajorVersion($lsb);
    if (($major == 27) || ($major == 28) || ($major == 29)
        || ($major == 30) || ($major == 31) || ($major == 32)
        || ($major == 33) || ($major == 34) || ($major == 35)
	|| ($major == 36) || ($major == 37) || ($major == 38)
	|| ($major == 39) || ($major == 40) || ($major == 41)) {
      return "FEDORA$major";
    }
  } elsif (isSles($host)) {
    my $result = assertCommand($host, "cat /etc/SuSE-release");
    if ($result->{stdout} =~ m/VERSION = 11/
        && $result->{stdout} =~ m/PATCHLEVEL = ([0-9]+)/) {
      return "SLES11SP$1";
    }
  }
  croak("unknown distro found on $host");
}

##########################################################################
# Fetches the release info when given the codename. By default, it returns
# the release info of the current release.
#
# @oparam    codename   The codename of the release to fetch info for.
#
# @return A hashref containing all the release info.
##
sub getReleaseInfo {
  my ($codename) = assertMinMaxArgs([$CODENAME], 0, 1, @_);
  my @found = grep(/^\Q$codename\E\s/, @RELEASE_MAPPINGS);
  if (scalar(@found) != 1) {
    croak("Found wrong number of results: '@found'");
  }

  my (undef, $ver, $suites, $tag) = split(/\s+/, $found[0]);
  my @suiteList = split(',', $suites);
  return {
           version        => $ver,
           suites         => \@suiteList,
           relTag         => $tag,
           defaultRelease => $suiteList[0],
         }
}

######################################################################
# Check if this variable has a number.
#
# @param     arg        value to test
# @return    true iff variable is a number
##
sub _isNumeric {
  my ($arg) = assertNumArgs(1, @_);
  return scalar($arg =~ /^[-+]?[0-9.]+$/);
}

######################################################################
# Check if this host is running Linux.
##
sub isLinux {
  my ($host) = assertMinMaxArgs(['localhost'], 0, 1, @_);
  return machineType($host) eq "Linux";
}

######################################################################
# Check if this host is running Windows/Cygwin.
##
sub isWindows {
  my ($host) = assertMinMaxArgs(['localhost'], 0, 1, @_);
  return machineType($host) eq "Cygwin";
}

######################################################################
# Check if this host is running the SLES11SP2 release.
##
sub isSles11SP2 {
  return (isSles()
          && _isNumeric(_getSlesVersion())
          && (_getSlesVersion() == $SLES11SP2_VERSION));
}

######################################################################
# Check if this host is running the SLES11SP3 release
##
sub isSles11SP3 {
  return (isSles()
          && _isNumeric(_getSlesVersion())
          && (_getSlesVersion() == $SLES11SP3_VERSION));
}

######################################################################
# Check if a host is running something prior to Debian Lenny.
#
# @param host   The host
##
sub isPreLenny {
  my ($host) = assertMinMaxArgs(['localhost'], 0, 1, @_);
  my $lsb = _getLsbRelease($host);
  return (_lsbReleaseMatches($lsb, "Debian")
          && ($lsb->{Release} lt $LENNY_DEBIAN_VERSION));
}

#######################################################################
# Check if a host is running Fedora and using the linux-next kernel.
# If the host is, uname kernel-release contains the keyword "next".
#
# @param host   The host
##
sub isFedoraNext {
  my ($host) = assertMinMaxArgs(['localhost'], 0, 1, @_);
  my $lsb = _getLsbRelease($host);
  if (_lsbReleaseMatches($lsb, "Fedora")) {
    return (assertCommand($host, "uname -r")->{stdout}
            =~ m/.*.*next.*fc.*x86_64/);
  }
  return 0;
}

######################################################################
# Helper (non-croaking) function for getSlesVersion().
##
sub _getSlesVersion {
  assertNumArgs(0, @_);
  if (isSles()) {
    if ($SLES_VERSION) {
      return $SLES_VERSION;
    }
    my $major;
    my $minor;

    open (my $verFile, '<', $SLES_VER_FILE)
      || croak("Could not open $SLES_VER_FILE ($ERRNO)");
    my @version = <$verFile>;
    close($verFile);

    map { if ($_ =~ /^VERSION = ([0-9]+)$/) { $major = $1; }
          if ($_ =~ /^PATCHLEVEL = ([0-9]+)$/) { $minor = $1;} } @version;

    $SLES_VERSION = "$major.$minor";
    return $SLES_VERSION;
  } else {
    return 0;
  }
}

######################################################################
# Gets the Permabit codename corresponding to the set of installed
# packages on the machine.
#
# @croaks if we can't determine the codename.
##
sub getPkgBundle {
  return _getInstalledRelease()
    || croak("Can't determine the Permabit release");
}

######################################################################
# Helper (non-croaking) function for getPkgBundle().
##
sub _getInstalledRelease {
  $INSTALLED_RELEASE ||= _getPattern($CUR_REL_FILE, qr/^[a-z]/);
  return $INSTALLED_RELEASE;
}

######################################################################
# Get the contents of a file if it matches a pattern.
#
# @param  filename    The name of a file.
# @param  pattern     A pattern to match.
##
sub _getPattern {
  my ($filename, $pattern) = assertNumArgs(2, @_);
  if (!isLinux()) {
    return;
  }

  my $version = _getFirstLine($filename);
  if (!defined($version) || $version =~ $pattern) {
    return $version;
  } else {
    $log->error("$version not in expected format: $pattern.");
    return;
  }
}

######################################################################
# Gets the first line of a file.
#
# @return a chomped string or undef if the file was empty or
#  doesn't exist.
##
sub _getFirstLine {
  my ($filename) = assertNumArgs(1, @_);

  if (-e $filename) {
    open(my $fh, "<", $filename);
    my $version = <$fh>;
    close($fh);

    if (defined($version)) {
      chomp($version);
      return $version;
    } else {
      $log->error("$filename was empty.");
    }
  } else {
    $log->warn("$filename does not exist.");
  }
  return;
}

######################################################################
# Generates cookie-cutter subs that check if a machine is a given
# release (i.e. isStatler(), isWaldorf(), ...).
##
BEGIN {
  no strict 'refs';
  foreach my $release (@CODENAMES) {
    my $subName = "is" . ucfirst($release);
    # XXX: change to die() after isStatler() method is no longer needed.
    if (!defined(*$subName)) {
      *$subName = sub {
        my $currentRelease = _getInstalledRelease();
        return defined($currentRelease) && $currentRelease eq $release;
      };
      push(@EXPORT_OK, $subName);
    }
  }
}

######################################################################
# Generates cookie-cutter subs that check if a machine is a given
# distribution and release thereof (i.e. isDebian(), isSqueeze(), ...).
##
BEGIN {
  no strict 'refs';
  our $KNOWN_DISTRIBUTIONS = {
    ubuntu => "Ubuntu",
    debian => "Debian",
    redHat => "RedHatEnterprise.*", # Server, Client, Workstation, ...
    fedora => "Fedora",
    sles   => "SUSE LINUX",
    centOS => "CentOS",
  };

  # If a release is purely numerals an 'is...' sub will be generated named
  # for the distribution and said release.  For example, centOS has a release
  # of '8' this results in the generation of the sub isCentOS8.
  # This was added as CentOS 8 (which is an Ootpa release) does not identify
  # itself as Ootpa thus necessitating a specific CentOS major number check
  # which is used in conjunction with isOotpa.
  our $KNOWN_RELEASES = {
    ubuntu => [qw(precise raring trusty vivid xenial)],
    debian => [qw(jessie lenny squeeze wheezy)],
    redHat => [qw(Santiago Maipo Ootpa Plow Coughlan)],
    fedora => [qw(TwentySeven TwentyEight TwentyNine Thirty ThirtyOne
	          ThirtyTwo ThirtyThree ThirtyFour ThirtyFive ThirtySix 
	          ThirtySeven ThirtyEight ThirtyNine Forty FortyOne Rawhide)],
    sles   => [],
    centOS => [qw(8)],
   };

  foreach my $distro (keys %$KNOWN_DISTRIBUTIONS) {
    my $subName = "is" . ucfirst($distro);
    *$subName = sub {
      my ($host) = assertMinMaxArgs(['localhost'], 0, 1, @_);
      return _isRelease($host, $KNOWN_DISTRIBUTIONS->{$distro});
    };
  }

  foreach my $distro (keys(%$KNOWN_DISTRIBUTIONS)) {
    foreach my $release (@{$KNOWN_RELEASES->{$distro}}) {
      my $subName;
      if (_isNumeric($release)) {
        $subName = "is" . ucfirst($distro) . $release;
        *$subName = sub {
          my ($host) = assertMinMaxArgs(['localhost'], 0, 1, @_);
          return _isRelease($host, $KNOWN_DISTRIBUTIONS->{$distro})
                  && (_getDistributionMajor($host) == $release);
        };
      } else {
        $subName = "is" . ucfirst($release);
        *$subName = sub {
          my ($host) = assertMinMaxArgs(['localhost'], 0, 1, @_);
          return _isRelease($host, $KNOWN_DISTRIBUTIONS->{$distro}, $release);
        };
      }
    }
  }
}


1;
