#!/usr/bin/perl
# -*-cperl-*-

##
# Check if a server is ready to be released back to the general pool.
#
# @synopsis
#
# checkServer.pl [--fix] [--user USERNAME] [--force] [-n] [--verbose] [--noRun]
#
# @level{+}
#
# @item B<--fix>
#
# Fix this machine instead of printing what's wrong with it.  Must be
# run as root.
#
# @item B<--user USERNAME>
#
# Perform checks on behalf of USERNAME.
#
# @item B<--force>
#
# USE WITH CAUTION: override the RSVP check.  With this option, machines
# can be fixed even when not owned by the current user.
#
# @item B<-n>
#
# Describe what fixes would have been performed, without running them.
#
# @item B<--verbose>
#
# Display the names of the tests that are run as they are being run.
#
# @item B<--noRun>
#
# Display the names of the tests that would be run, but don't actually run
# them.
#
# @item B<--debug>
#
# Display debugging messages.
#
# @level{-}
#
# @description
#
# Check a server for the most common reasons tests are not able to run.
#
# Doesn't check for processes on the machine, this is handled separately by
# the rsvp process (Permabit/RSVP.pm) so that it can do per-user checks.
#
# You should test your changes to this file by:
#   cd src/perl/Permabit ; ./runtests.pl CheckServer_t1
#
# $Id$
##
use strict;
use warnings FATAL => qw(all);

use B qw(svref_2object);
use Carp qw(croak);
use English qw(-no_match_vars);
use File::Basename qw(dirname);
use File::Find ();
use File::stat;
use Getopt::Long;
use IO::Dir;
use IO::File;
use Log::Log4perl qw(:easy);
use Socket;

use FindBin;
use lib "${FindBin::RealBin}/../lib";

use Permabit::CheckServer::Constants;
use Permabit::CheckServer::Utils qw(
  dnsConfiguration
  fqdnSuffix
);
use Permabit::AsyncSub;
use Permabit::Constants;
use Permabit::Internals::CheckServer::Host;
use Permabit::Triage::TestInfo qw(:albireo);
use Permabit::Utils qw(
  findExecutable
  getScamVar
  hostToIP
);
use Permabit::PlatformUtils qw(
  getClocksource
  getPkgBundle
  isAlbireo
  isCentOS
  isCentOS8
  isFedora
  isFedoraNext
  isMaipo
  isOotpa
  isPlow
  isRedHat
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
  isRawhide
);

# These are used all over the place hence their position here at the
# very top of the file
my $arch             = uc(`uname -m`);
my $HOSTNAME         = `hostname`;
my $kernel           = `uname -r`;
my $machine          = `uname -m`;
chomp($arch, $HOSTNAME, $kernel, $machine);
my ($SHORT_HOSTNAME) = split(/\./, "$HOSTNAME");

my %REQUIRED_PACKAGES;

# The following is used as a global marker to ensure that something
# happens even if something bad happens
my $loaded;
END {
  if (!$loaded) {
    # Make sure this prints FAILURE even if it cannot run
    print "FAILURE\nUnable to run $0\n";
  }
}

# For per-check timings, try: '%-23d{ISO8601} %-5p [%5P] %m%n' and $DEBUG
Log::Log4perl->easy_init({layout => '%m%n',
                          level  => $WARN,
                          file   => "STDOUT"});
my $log = Log::Log4perl->get_logger('checkServer');

# Start setting up the constants that are going to be used by the script
my $NICS = '0';
# Minimal amount of memory (in kB)
my $MIN_MEMORY = 950 * 1024;

# Declare the various global variables
my @fixes;
my $kernelModSuffix = 'ko';
my @warnings;
my $fix = 0;
my $reboot = 0;
my $softupdate = 0;
my @disks;
# used by _getRSVPClasses to cache answer
my @rsvpClasses      = ();

# XXX This is declared using constants formatting, but isn't really one
my $CURRENT_KERNELS;

# Set the environment paths.
sub _setPaths {
  my @pathDirs = qw(/usr/local/sbin
                    /usr/local/bin
                    /usr/sbin
                    /usr/bin
                    /sbin
                    /bin
                    /usr/X11R6/bin);
  $ENV{PATH} = join(':', @pathDirs);
}

# Set paths for command resolution.
_setPaths();

# XXX Make updates to the "constants" that are stored seperately
if (_isVirtual()) {
  delete $DAEMONS{ntpd};
}

delete $DAEMONS{cron};
$DAEMONS{crond} = 'crond';

# TODO This all needs to be split up in to proper functions as well as
# TODO constants in Constants.pm
#
# Albireo
#
if (isAlbireo()) {
  foreach my $moduleName (keys(%testModules)) {
    push(@BAD_FILES,
         "/lib/modules/$kernel/kernel/drivers/block/$moduleName.ko",
         "/lib/modules/$kernel/updates/dkms/$moduleName.ko");

    push (@BAD_FILES,
          "/etc/rc.d/init.d/$moduleName");

    # Add any init.d scripts for specific devices created by modules.
    my $lsmodResult = `lsmod`;
    if ($lsmodResult =~ /$moduleName/ ) {
      my $targetNames = $testModules{$moduleName};
      my @deviceLists = map { `sudo dmsetup ls --target $_` } @$targetNames;
      for my $line (map { split("\n", $_) } @deviceLists) {
        if ($line !~ /No devices found/ && $line =~ /(\S+)\s+.*/) {
          push (@BAD_FILES,
                "/etc/rc.d/init.d/$1");
        }
      }
    }
  }
  if (!isOotpa() && !isMaipo()) {
    push(@BAD_FILES, "/u1/zubenelgenubi*");
  }

  if (isMaipo()) {
    $CURRENT_KERNELS = '3.10.0-.*\.el7(|\.pbit[0-9]+).x86_64';
  } elsif (isOotpa() || isCentOS8()) {
    $CURRENT_KERNELS =
      '4.18.0-.*\.(|1.2.)el8(|_[0-9])(|\.v[0-9]+).x86_64(|\+debug)';
  } elsif (isPlow()) {
    $CURRENT_KERNELS = '5.14.0-.*.el9(|_([0-9])).x86_64(|\+debug)';
  } elsif (isFedoraNext()) {
    $CURRENT_KERNELS = '.*.*next.*fc.*x86_64';
  } elsif (isTwentySeven()) {
    $CURRENT_KERNELS = '4.*.fc27.x86_64';
  } elsif (isTwentyEight()) {
    $CURRENT_KERNELS = '(4|5).*.fc28.x86_64';
  } elsif (isTwentyNine()) {
    $CURRENT_KERNELS = '(4|5).*.fc29.x86_64';
  } elsif (isThirty()) {
    $CURRENT_KERNELS = '5.*.fc30.x86_64';
  } elsif (isThirtyOne()) {
    $CURRENT_KERNELS = '5.*.fc31.x86_64';
  } elsif (isThirtyTwo()) {
    $CURRENT_KERNELS = '5.*.fc32.x86_64';
  } elsif (isThirtyThree()) {
    $CURRENT_KERNELS = '5.*.fc33.x86_64';
  } elsif (isThirtyFour()) {
    $CURRENT_KERNELS = '5.*.fc34.x86_64';
  } elsif (isThirtyFive()) {
    $CURRENT_KERNELS = '(5|6).*.fc35.x86_64';
  } elsif (isThirtySix()) {
    $CURRENT_KERNELS = '(5|6).*.fc36.x86_64';
  } elsif (isThirtySeven()) {
    $CURRENT_KERNELS = '6.*.fc37.x86_64';
  } elsif (isThirtyEight()) {
    $CURRENT_KERNELS = '6.*.fc38.x86_64';
  } elsif (isThirtyNine()) {
    $CURRENT_KERNELS = '6.*.fc39.x86_64';
  } elsif (isForty()) {
    $CURRENT_KERNELS = '6.*.fc40.x86_64';
  } elsif (isRawhide()) {
    # Since Fedora Rawhide's kernel changes so frequently
    # we can only check basic formatting.
    $CURRENT_KERNELS =  '\d+\.\d+\..*fc\d{2}\.x86_64';
  }
}

main();
exit(0);

######################################################################
# Check that this server is ready to be released
##
sub main {
  $log->debug("starting main");
  if (!isRoot()) {
    my @sudoArgs = ($0, @ARGV);
    # Which environment variables do we need to preserve?
    #
    # If a user specifies an RSVP server, don't lose track and then
    # override it below.
    if ($ENV{PRSVP_HOST}) {
      unshift(@sudoArgs, "PRSVP_HOST=$ENV{PRSVP_HOST}");
    }
    exec('sudo', @sudoArgs);
  }

  # Note the command line arguments
  $loaded = 1;
  my $debug = 0;
  my $dryRun = 0;
  my $force = 0;
  my $noRun = 0;
  my $user;
  my $verbose = 0;
  if (!GetOptions(
                  "debug!"      => \$debug,
                  "fix!"        => \$fix,
                  "force!"      => \$force,
                  "noRun!"      => \$noRun,
                  "user=s"      => \$user,
                  "verbose!"    => \$verbose,
                  "n!"          => \$dryRun,
                  "help!"       => sub {
                    require Pdoc::Generator;
                    import Pdoc::Generator qw(pdoc2help);
                    pdoc2help();
                  },
                 ) || @ARGV) {
    require Pdoc::Generator;
    import Pdoc::Generator qw(pdoc2usage);
    pdoc2usage();
  }

  if ($verbose || $noRun) {
    $log->level($INFO);
  }

  if ($debug) {
    $log->level($DEBUG);
  }

  if ($dryRun && $fix) {
    print STDERR "Use -n or --fix, but not both.\n";
    exit(1);
  }

  # A large collection of mostly small tests to be run. Each one that
  # finds a problem can register a shell command to fix it, and if
  # "--fix" was given, they'll be applied in order.
  my @tests = (
    \&checkPerlConfig,
    \&checkVarCrash,
    \&checkSystemSpace,
    \&checkMounts,
    \&checkBadFiles,
    \&checkBadDirs,
    \&checkBadPrograms,
    \&checkCanWrite,
    \&checkU1,
    \&checkPermissions,
    \&checkISCSITarget,
    \&checkISCSIInitiator,
    (_isDevVM() || _isBeaker()) ? () : \&checkPermabitHostname,
    \&checkPMIFarm,
  );
  # Additional checks that we want to run concurrently with the above.
  # Any fixes provided by them are applied after the fixes for the
  # serial checks above, and in the order that the checks are found in
  # this list.
  #
  # Good candidates for this list are checks that take a long time to
  # run, or involve waiting on resources (such as the RSVP server, or
  # to some degree even local disk) while we could be doing something
  # else. This needs to be balanced with the resource limitations
  # (CPU, disk bandwidth) of the host, which vary across platforms; we
  # can't just launch everything asynchronously and cause a load spike
  # to 50 without causing new bottlenecks.
  my @asyncTests = (
    \&checkRunningPrograms,
  );

  require Permabit::RSVP;
  import Permabit::RSVP;
  require YAML;
  import YAML qw(LoadFile);

  unshift(@asyncTests,
          \&checkRSVPClasses,
         );
  if (!_isVirtual()) {
    push(@tests,
         \&checkSmartEnabled);
  }
  push(@asyncTests,
       \&checkDKMS,
       \&checkKernLog,
       \&checkPackages,
       \&checkTestStorageDevice,
      );
  push(@tests,
       (_isAnsible()) ? () : \&checkKernel,
       \&checkDaemons,
       (_isAnsible()) ? () : \&checkDNS,
       \&checkLoopDevices,
       \&checkNFSMounts,
       \&checkFstab,
       # Do not check bunsen system unless it is
       # pfarm or jfarm.
       (_isAnsible() && !(_isJFarm() || _isPFarm())) ? () : \&checkSSHkey,
       \&checkSSHDconfig,
       \&checkSudoers,

       \&checkMemory,
       ($machine eq 's390x') ? () : \&checkKDumpConfig,
       # Disabled the check on machines for public github testing, ossbunsen farms
       ($machine eq 's390x' || $HOSTNAME =~ /^ossbunsen-farm-/)
          ? () : \&checkKExecLoaded,
       \&checkClocksource,
       \&checkLVM,
       \&checkLVMConf,
       \&checkModules,
       \&checkPythonHacks,
      );

  $log->debug("built test list");
  # This will hold running async subs; each async sub will return a
  # hash with array refs under the names "warnings" and "fixes".
  my @asyncSubs;
  foreach my $test (@asyncTests) {
    # Display the name of the test before it is run if need be
    my $sv = svref_2object($test);
    my $gv = $sv->GV;
    my $name = $gv->NAME;
    $log->info("async: $name");
    my $code = sub {
      if (!$noRun) {
        &$test();
      }
      $log->debug("done: $name");
      return {
              'name'     => $name,
              'warnings' => \@warnings,
              'fixes'    => \@fixes
             };
    };
    my $asyncSub = Permabit::AsyncSub->new(code => $code);
    $asyncSub->start();
    push(@asyncSubs, $asyncSub);
  }
  foreach my $test (@tests) {
    # Display the name of the test before it is run if need be
    my $sv = svref_2object($test);
    my $gv = $sv->GV;
    $log->info($gv->NAME);
    if (!$noRun) {
      &$test();
    }
  }
  $log->debug("await async test results");
  foreach my $asyncSub (@asyncSubs) {
    # Display the name of the test before it is run if need be
    my $result = $asyncSub->result();
    $log->debug("collected $result->{name}");
    push(@warnings, @{$result->{warnings}});
    push(@fixes, @{$result->{fixes}});
  }
  $log->debug("finished test list");

  if ($fix) {
    # Do not allow anyone to fix a Linux machine that they have not
    # reserved (unless they use the secret --force option)
    if (!$force) {
      eval {
        my $rsvp = Permabit::RSVP->new();
        $rsvp->verify(host => $HOSTNAME,
                      user => ($user || $ENV{SUDO_USER} || $ENV{USER}));
      };
      if ($EVAL_ERROR) {
        print STDERR "rsvp: $EVAL_ERROR";
      }
    }
    foreach my $fix (@fixes) {
      # Ignore errors, have stdout && stderr be shown to the user
      print STDERR "Performing fix: $fix\n";
      system($fix);
    }
    if ($reboot) {
      print STDERR "We would like to suggest rebooting\n";
    }
  } elsif ($dryRun) {
    foreach my $fix (@fixes) {
      print STDERR "Would have performed fix: $fix\n";
    }
  } elsif (!$noRun) {
    if (scalar(@warnings)) {
      print "FAILURE\n";
      print join("\n", @warnings) . "\n";
    } else {
      print "success\n";
    }
  }
}

######################################################################
# Add an error message (and optionally a fix).
#
# @oparam warning       The warning message to print
# @oparam fix           The command to run to fix this error
##
sub error {
  my ($warning, $fix) = @_;
  if ($warning) {
    push(@warnings, $warning);
  }
  if ($fix) {
    push(@fixes, $fix);
  }
}

######################################################################
# Check if we're user root
##
sub isRoot {
  return (($UID == 0) || ($EUID == 0));
}

sub checkPMIFarm {
  my @deviceList=("vdc", "vdd", "vde", "vdf", "vdg");
  if (!_isPMIFarm()) {
    return;
  }
  foreach my $device (@deviceList) {
    my $hasFS = `wipefs -n /dev/$device`;
    if ($hasFS ne "") {
      push(@fixes, "wipefs --all --force /dev/$device");
      push(@fixes, "dd if=/dev/zero of=/dev/$device bs=1M count=2000");
      error("$device is not clean, $hasFS");
    }
  }
 return;
}

######################################################################
# Check that /u1 isn't too full and that it is at least the correct
#   size for the server that it is on.
# In the event that it is too full under --fix: removes files older
#   than 7 days and then delete empty directories.
# In the event that the /u1 directory is too small under --fix: issues
#   a mount -a command which should generally resolve the problem if
#   the system is properly configured.
##
sub checkU1 {
  # First, resolve the device that /u1 resides on
  my $device = _getPartitionDevice("/u1");

  # First, check to make sure /u1 has the proper disk size
  my $size = $DEFAULT_U1_SIZE;
  if (($device ne "none") && (_getPartitionSize($device) < $size)) {
    error("/u1 is too small, $size or more expected.", "mount -a");
  }

  # Next, check to make sure it is not too full
  my $limit = $U1_LIMIT;
  if (_isFarm()) {
    if (_isVirtual()) {
      $limit = $VFARM_U1_LIMIT;
    } else {
      $limit = $FARM_U1_LIMIT;
    }
  }
  my $avail = _getPartitionAvailableSize("/u1");

  # Prepare the command to remove files from /u1
  my $removeCmd = 'find /u1 -mtime +7 -type f -print | xargs rm -f && '
      . 'find /u1 -depth -type d '
      . '-print '
      . '| xargs rmdir 2> /dev/null';
  if ($avail < $limit) {
    error("/u1 too full ($avail < $limit)", $removeCmd);
  }
}

######################################################################
# Check system disk space:
# root needs $ROOT_LIMIT bytes
# /var needs $VAR_LIMIT bytes
# /var/log needs $VAR_LIMIT bytes
# These may not be separate filesystems
##
sub checkSystemSpace {
  my %fsRequired = ("/"        => $ROOT_LIMIT,
                    "/var"     => $VAR_LIMIT,
                    "/var/log" => $VAR_LIMIT,
                   );

  my %devRequired = ();
  my %devAvailable = ();
  my %deviceFs = ();
  my %fsDevice = ();
  my $regexp = '^/dev/(\S+)\s+\d+\s+\d+\s+(\d+)\s+\d+%\s+/.*$';
  foreach my $fs ("/", "/var", "/var/log") {
    my $output = `df -P -k $fs`;
    if ($output =~ m/$regexp/m) {
      my $device = $1;
      my $available = $2;
      $available *= 1024;        # convert to bytes
      $fsDevice{$fs} = $device;
      if (!exists($devRequired{$device})
          or ($devRequired{$device} < $fsRequired{$fs})) {
        $devRequired{$device} = $fsRequired{$fs};
        $devAvailable{$device} = $available;
        $deviceFs{$device} = $fs;
      }
    }
  }
  foreach my $dev (sort(keys(%devRequired))) {
    my $available = $devAvailable{$dev};
    my $required = $devRequired{$dev};
    if ($available < $required) {
      my @purgeLogs = ();
      if ($fsDevice{"/var/log"} eq $dev) {
        push(@purgeLogs, "sudo journalctl --vacuum-size=$available");
        chomp(my $cmd = `which logrotate`);
        if (($cmd =~ m/logrotate/) && (-x $cmd)) {
          push(@purgeLogs, "sudo $cmd --force /etc/logrotate.conf");
        }
      }
      if (@purgeLogs) {
        @purgeLogs = (join(" && ", @purgeLogs));
      }
      error("'$deviceFs{$dev}' is too full, ($available < $required)",
            @purgeLogs);
    }
  }
}

######################################################################
# Check that the perl.yaml config file is present.
##
sub checkPerlConfig {
  if (! -r '/etc/permabit/perl.yaml') {
    error("/etc/permabit/perl.yaml missing");
  }
}

######################################################################
# Check that /var/crash is empty.
#   under --fix: Moves all crash files to a directory in
#                /permabit/not-backed-up
#
# Using a complicated invocation of File::Find as
# there are diverse uses which get made of /var/crash.
##
sub checkVarCrash {
  if (! -d  '/var/crash') {
    return;
  }
  my $dst =  "/permabit/not-backed-up/crash/$HOSTNAME-" .
    `date +'%Y-%m-%dT%H:%M:%S'`;
  chomp($dst);
  my $removeCmd    = "mkdir -p $dst && chmod g+wrxs $dst ";
  my $appRemoveCmd = "&& mv /var/crash/\*crash $dst/ ";
  my $fail = 0;

  # Some applications leave these.
  my @appCrashFiles = glob("/var/crash/*crash");
  # Filter out any known crashes we don't care about.
  foreach my $ignoreRegexp (@IGNORE_CRASH_PATTERNS) {
    @appCrashFiles = grep($_ !~ $ignoreRegexp, @appCrashFiles);
  }
  if (scalar(@appCrashFiles) > 0) {
    $removeCmd .= $appRemoveCmd;
    $fail = 1;
  }

  our @kernelCrashDirs;
  my $wanted = sub {
    # Note: not y3K compliant.
    # covers RHEL formatted crashdirs.
    if (/^(127\.0\.0\.1-)?2[\d\-:]+\z/s) {
      push(@kernelCrashDirs, $File::Find::name);
      print "Found $File::Find::name\n";
    }
  };

  File::Find::find({wanted => $wanted}, '/var/crash');
  if (scalar(@kernelCrashDirs) > 0) {
    $fail = 1;
    foreach (@kernelCrashDirs) {
      $removeCmd .= "&& mv $_ $dst ";
    }
  }

  if ($fail) {
    error("Crash files or directories in /var/crash:  "
          . join(" ", @kernelCrashDirs, @appCrashFiles),
          $removeCmd);
  }
}

######################################################################
# Check for mounts
##
sub checkMounts {
  open(my $mh, "mount 2>/dev/null|") || _die("unable to run mount: $ERRNO");
  my %requiredMounts;
  while (<$mh>) {
    chomp();
    if (m,on (/mnt/\S+|/u1/\S+)\s+,) {
      if (exists $requiredMounts{$1}) {
        ++$requiredMounts{$1};
      } else {
        error("$_ mounted", "umount -f $1");
      }
    }
  }
  close($mh) || _die("unable to run mount: $CHILD_ERROR");

  foreach my $mnt (keys %requiredMounts) {
    if ($requiredMounts{$mnt} != 1) {
      error("$mnt not mounted", "mount $mnt");
    }
  }
}

######################################################################
# Given two sets, return the list of keys from the first set that aren't in the
# second set.
#
# @param set1   the first hashref
# @param set2   the second hashref
#
# @return       the list of keys
##
sub _setDifference {
  my ($set1, $set2) = @_;
  my %result = %$set1;
  foreach my $k (keys(%$set2)) {
    if (exists ($result{$k})) {
      delete $result{$k};
    }
  }
  return keys(%result);
}

######################################################################
# Check for installed packages that shouldn't be there
##
sub checkPackages {
  my $mapRE;
  my $pkgCmd;

  $pkgCmd = 'rpm -qa --qf \'%{Name}.%{arch}:%{Version}-%{Release}\n\' \
        | egrep -v \'(gpg-pubkey|beaker-)\'';
  $mapRE = '^(.*):(.*)$';
  # generate the hash of already installed packages
  open(my $ph, "env COLUMNS=300 $pkgCmd 2>/dev/null |")
    || _die("couldn't run $pkgCmd; OS_ERROR = \"$OS_ERROR\"");
  my @packages = <$ph>;
  close($ph) || _die("couldn't run $pkgCmd: $CHILD_ERROR");
  my %installed = map { /$mapRE/ } @packages;

  # Compare what is currently installed against what we installed during
  # provisioning and throw an error for any extraneous packages that were not
  # installed during provisioning.
  my @extraPackages;
  if (-e "/etc/required_packages") {
    my ($required_packages) = LoadFile("/etc/required_packages");
    if ((ref($required_packages) ne 'HASH')
        || (keys(%$required_packages) == 0)) {
      _die("Incorrect format for /etc/required_packages file");
    }
    %REQUIRED_PACKAGES = %$required_packages;
    push(@extraPackages,
         _setDifference(\%installed, \%REQUIRED_PACKAGES));
  }

  my $beakerExclusionRE = qr/^gpm-libs|vim-(common|enhanced)/;
  my @removePackages;
  foreach my $package (@extraPackages) {
    # We exclude some packages here because permabit lab machines require them
    # but beaker infrastructure tasks install them on beaker systems and we
    # need to ignore them.
    if ($installed{$package} && ($package !~ $beakerExclusionRE)) {
      push(@removePackages, $package);
    }
  }
  if (@removePackages) {
    my $s = join(' ', @removePackages);
    error("packages $s installed",
           (isCentOS() || isRedHat()) ? "yum remove -y $s"
                                      : (isFedora()) ? "dnf remove -y $s"
                                                     : _die("unknown package manager"));
  }

  my @missingPackages;
  %installed = ();

  #Check version mismatch from installed and /etc/required_packages [OPS-4684]
  foreach my $insPackage (@packages) {
    my $ignore;
    my $sw;
    my $ver;
    ($ignore, $sw, $ver) = split /$mapRE/, $insPackage;
    $installed{$sw} = $ver;
    if (!defined($REQUIRED_PACKAGES{$sw})) {
      if ($sw !~ $beakerExclusionRE) {
        error("$sw: $ver installed but not in /etc/required_packages");
      }
      next;
    }
    if ($REQUIRED_PACKAGES{$sw} ne $ver) {
      error("$sw version mismatch: required $REQUIRED_PACKAGES{$sw} got $ver");
    }
  }

  foreach my $package (keys(%REQUIRED_PACKAGES)) {
    if (!$installed{$package}) {
      push(@missingPackages, $package);
    } else {
      my $ver = $REQUIRED_PACKAGES{$package};
      if (ref($ver) eq 'ARRAY') {
        if (scalar(grep { $_ eq $installed{$package} } @{$ver}) != 1) {
          error("Bad version of $package ($installed{$package}),"
                . " good versions: "
                . join(" ", @{$ver}),
                  (isCentOS() || isRedHat()) ? "yum install -y $package"
                                             : (isFedora()) ? "dnf install -y $package"
                                                            : _die("unknown package manager"));
        }
      } else {
        my $regexp;
        if (ref($ver) eq 'Regexp') {
          $regexp = $ver;
        } else {
          $regexp = qr/\Q$ver\E/;
        }
        if ($installed{$package} !~ $regexp) {
          #XXX: If we have multiple version of a package installed (but not all
          #     of them are listed in /etc/required_packages), then this error
          #     will show up.  It's not technically wrong, but can be confusing
          #     to see multiple errors, as there will also be a complaint about
          #     "version mismatch" above)
          error("Bad version of $package ($installed{$package}"
                . " !~ $ver)",
                (isCentOS() || isRedHat()) ? "yum remove -y $package && yum install -y $package"
                                           : (isFedora()) ? "dnf remove -y $package && dnf install -y $package"
                                                          : _die("unknown package manager"));
        }
      }
    }
  }

  if (@missingPackages) {
    my $pkgs = join(' ', @missingPackages);
    my $pkgsFix = join(' ', @missingPackages);
    error("Required package(s) $pkgs not installed",
          (isCentOS() || isRedHat()) ? "yum install -y $pkgsFix"
                                     : (isFedora()) ? "dnf install -y $pkgsFix"
                                                    : _die("unknown package manager"));
  }
}

######################################################################
# Check permissions on certain files and directories
##
sub checkPermissions {
  foreach my $dir (@CHECKED_DIRS) {
    _checkStaffPermissions($dir);
  }
  foreach my $dir (glob($BUILD_DIRS)) {
    _checkTriagePermissions($dir);
  }
  if (!isFedora()) {
    _checkRootWritePermissions("/sys/permatest/printk");
  }
  my $file = "/u1/zubenelgenubi";
  if (-f $file) {
    _checkStaffPermissions($file);
  }

  foreach my $g (@TEST_DIRS) {
    foreach my $dir (glob($g)) {
      my $stat = stat($dir) || _die("no such dir $dir");
      if ($stat->uid == 0) {
        my ($realOwner) = ($dir =~ m|/[[:alpha:]]+-(\w+)/?|);
        if ($realOwner eq 'root') {
          error("$dir not allowed to exist", "rm -rf $dir");
        } else {
          error("$dir is owned by root", "chown $realOwner:staff $dir");
        }
      }
    }
  }
}

######################################################################
# Get the list of physical disks (/dev/hd*, /dev/sd*, and /dev/xvd*
# are considered physical disks).
##
sub _getDisks {
  if (scalar(@disks) == 0) {
    open(my $fh, '<', '/proc/partitions')
      || _die("Couldn't open /proc/partitions: $ERRNO");
    while(<$fh>) {
      # matches: major minor  #blocks  (hda, sda, xvda, etc...)
      if (/^\s*\d+\s+\d+\s+\d+\s+((?:s|h|xv)d[a-z]+)$/) {
        push(@disks, $1);
      }
    }
  }
  return @disks;
}

######################################################################
# Check that the hostname is fully-qualified.
##
sub checkPermabitHostname {
  my $suffix = fqdnSuffix();
  if (defined($suffix)
      && (substr($HOSTNAME, -length($suffix)) ne $suffix)) {
    $HOSTNAME .= $suffix;
    error("Hostname not fully qualified",
          "echo $HOSTNAME > /etc/hostname; hostname $HOSTNAME");
  }
}

######################################################################
# Check if various bad files (including overrides files created by the
# permaserver package, and the permaserver-mgr crontab file) exist.
##
sub checkBadFiles {
  foreach my $file_or_glob (@BAD_FILES) {
    if (-f $file_or_glob) {
      error("$file_or_glob exists", "rm -f $file_or_glob");
    }
    foreach my $file (glob($file_or_glob)) {
      if (-f $file) {
        error("$file exists matching $file_or_glob", "rm -f $file");
      }
    }
  }
}

######################################################################
# Check if various bad directories exist.
##
sub checkBadDirs {
  foreach my $dir (@BAD_DIRS) {
    if (-d $dir) {
      error("$dir exists", "rm -rf $dir");
    }
  }
}

######################################################################
# Check if various of our programs are installed that shouldn't be
##
sub checkBadPrograms {
  foreach my $dir (@SYSTEM_BIN_DIRS) {
    foreach my $prog (@BAD_PROGRAMS) {
      my $file = "$dir/$prog";
      if (-f $file) {
        error("$file exists", "rm -f $file");
      }
    }
  }
}

######################################################################
# Check if various of our programs are running that shouldn't be
##
sub checkRunningPrograms {
  my $foundRunningProgram = 0;
  foreach my $prog (@BAD_PROGRAMS) {
    if (system("pgrep -f -x $prog >/dev/null") == 0) {
      error("$prog is running", "pkill -x $prog");
      $foundRunningProgram = 1;
    }
  }
  # Check for system processes that shouldn't be running
  foreach my $prog (@BAD_PROCESSES) {
    # Search the command line with pgrep -f because valgrind changes
    # the process name unlike the programs in @BAD_PROGRAMS
    if (system("pgrep -f '^$prog' >/dev/null") == 0) {
      error("$prog is running", "sudo kill `pgrep -f '^$prog'`");
      $foundRunningProgram = 1;
    }
  }
  # If we found any running programs, allow time for them to die
  if ($foundRunningProgram) {
    error("", "sleep 2");
  }
}

######################################################################
# Confirms that the kernel is using the right clocksource.
##
sub checkClocksource {
  if (_isVirtual() || _isBeaker ()) {
    return;
  }
  my $clocksrc = getClocksource();
  if ($clocksrc ne 'tsc') {
    error("clocksource is incorrect: expected 'tsc', got '$clocksrc'",
          _rebuildFromMach("configGrub"));
  }
}

######################################################################
# Return the device for a given path
##
sub getDeviceForPath {
  my $path = shift;
  my @devices = grep { /^\/dev/ } `df $path`;
  my ($dev) = split(/\s+/,$devices[0]);
  return($dev);
}

######################################################################
# Make sure it looks like DNS is setup correctly on this machine.
##
sub checkDNS {
  my $dns = {%{dnsConfiguration()}};
  if (%{$dns}) {
    my $conf = '/etc/resolv.conf';
    open(my $fh, $conf)
      || _die("Couldn't open resolv.conf: $ERRNO");
    while (<$fh>) {
      while (my ($k, $regexp) = each(%{$dns})) {
        if (/$regexp/) {
          delete $dns->{$k};
        }
      }
    }
    if (%{$dns}) {
      error("Invalid $conf. Couldn't find lines that matched:\n\t"
            . join("\n\t", values(%{$dns})),
            "dhclient");
    }
  }
}

######################################################################
# Make sure loop devices aren't left configured after tests.
##
sub checkLoopDevices {
  my @lines = split('\n', `sudo losetup -a`);
  for my $line (@lines) {
    my $device = $line;
    $device =~ s/:.*$//;
    if ((($line =~ m,/home/big_file,) || ($line =~ m,/big_file,))
        && (_isBeaker() || _isDevVM())) {
      next;
    }
    error("Loop device $device found",
          "sudo losetup -d $device");
  }
}

######################################################################
# Check that the ntp configuration matches the version in
# /permabit/mach/files.
##
sub checkNtpConfiguration {
  if (_isNTP()) {
    my $refNTPConf = "$MACH_DIR/files/ntp.conf";

    if (-f $refNTPConf . $SHORT_HOSTNAME) {
      $refNTPConf .= ".$SHORT_HOSTNAME;"
    }

    if (system("cmp -s $refNTPConf /etc/ntp.conf") != 0) {
      error("Invalid /etc/ntp.conf", _rebuildFromMach("ntp.conf"));
    }
  }
}

######################################################################
# Check that we're in the correct timezone (EDT)
##
sub checkTimeZone {
  my $correctZone = "/usr/share/zoneinfo/America/New_York";
  my $symlink     = "/etc/localtime";
  my $current     = readlink($symlink);
  my $makeLink    = "rm -f $symlink ; ln -s $correctZone $symlink";
  my $rmLink      = "rm $symlink";

  if (! -l $symlink) {
    error("$symlink is not a symlink (or does not exist)", $makeLink);
  } elsif ($correctZone ne $current) {
    error("I'm in the wrong time zone: $current", "$rmLink; $makeLink");
  }
}

######################################################################
# Check that required daemons are running
##
sub checkDaemons {
  foreach my $daemon (keys(%DAEMONS)) {
    #XXX: ntpd is not available in RHEL8, FEDORA32 and FEDORA33 anymore,
    #     we need to fix this at some point"
    if ((isCentOS8() || isOotpa() || isPlow() || isFedoraNext()
	 || isThirtyTwo() || isThirtyThree() || isThirtyFour()
	 || isThirtyFive() || isThirtySix() || isThirtySeven()
	 || isThirtyEight() || isThirtyNine() || isForty())
        && $daemon eq "ntpd") {
      next;
    }
    if (system("bash", "-c", "pgrep -x '^${daemon}\$' &>/dev/null") != 0) {
      if ($daemon eq 'smartd' && _isVirtual()) {
        next;
      }
      if ($daemon ne "smartd" || $kernel !~ /^2\.4\.32pcore-a\.15$/) {
        if (defined($DAEMONS{$daemon})) {
          error("Daemon $daemon not running",
                "service $DAEMONS{$daemon} restart");
        } else {
          error("Daemon $daemon not running");
        }
      }
    }
  }
}

######################################################################\
# Check that the kernel is correct.
##
sub checkKernel {
  if (ref($CURRENT_KERNELS) eq 'ARRAY') {
    if (scalar(grep {$kernel eq $_} @{$CURRENT_KERNELS}) == 0) {
      error("Bad kernel: $kernel, not one of "
            . join(" ", @{$CURRENT_KERNELS}));
    }
  } elsif ($kernel !~ /$CURRENT_KERNELS/) {
    error("Bad kernel: $kernel");
  }
}

######################################################################
# Check the RSVP class membership
##
sub checkRSVPClasses {
  # No classes or in MAINTENANCE skips everything else
  # XXX Why would something have no classes?
  if ((! _getRSVPClasses()) || _isInClass('MAINTENANCE')) {
    return;
  }

  # Everything should always be in ALL
  _assertMember('ALL');

  my @goodClasses = qw(ALL);

  # PMI machines should only be in the classes PMI, ALL (when relevant),
  # VDO (when relevant)
  if (_isAlbPerf() || _isVDOPerf()) {
    # If we're running a Fedora release, then set the more generic
    # "superclass".
    # Also, since Fedora is one of the targets for //eng/linux-uds and
    # //eng/linux-vdo usage, add the LINUX-UDS, and LINUX-VDO class
    # respectively.
    if (isFedora()) {
      push(@goodClasses, 'FEDORA', 'LINUX-UDS', 'LINUX-VDO');
    }

    # Since CentOS/RHEL8 (Ootpa) is the target for //eng/linux-uds,
    # //eng/linux-vdo and //eng/vdo usage, add the LINUX-UDS, LINUX-VDO
    # respectively.
    if (isCentOS8() || isOotpa() || isPlow()) {
      push(@goodClasses, 'LINUX-UDS', 'LINUX-VDO');
    }

    push(@goodClasses, 'VDO');
  }

  # Check whether we're on a pmifarm and therefore make sure we're a member of
  # both ALBIREO-PMI, and VDO-PMI.
  #XXX: Note that the current existence of ALBIREO-PMI, and VDO-PMI being
  #     separate entities is on its way out.  Upon which, this section will
  #     succeed the next one, and then eventually the classes will be combined.
  if (_isPMIFarm()) {
    push(@goodClasses, 'ALBIREO-PMI', 'VDO-PMI');

    _assertMemberOfOnly(@goodClasses,
                        uc(_getOsClass()),
                        $arch);

    return;
  }

  if (_isAlbPerf()) {
    push(@goodClasses, 'ALBIREO-PMI');

    _assertMemberOfOnly(@goodClasses,
                        uc(_getOsClass()),
                        $arch);

    return;
  }
  _assertNotMember('ALBIREO-PMI');

  if (_isVDOPerf()) {
    push(@goodClasses, 'VDO-PMI');

    _assertMemberOfOnly(@goodClasses,
                        uc(_getOsClass()),
                        $arch);

    return;
  }
  _assertNotMember('VDO-PMI');

  # Check that the basic assumptions apply to everything else
  _assertMemberArchClass();
  _assertMemberOsClass();
  _assertMemberPkgBundle();

  # Run the various check functions and make sure the class is or is not
  # present on the basis of the return value
  my %classMap = (
    FARM             => \&_isFarm,
    FEDORA           => sub { return (isFedora()) },
    JFARM            => \&_isJFarm,
    "LINUX-UDS"      => sub { return (isCentOS8() || isFedora()
                                      || isOotpa() || isPlow()) },
    "LINUX-VDO"      => sub { return (isCentOS8() || isFedora()
                                      || isOotpa() || isPlow()) },
    PFARM            => \&_isPFarm,
    # Everything should currently be able to run VDO.
    #XXX: Of course this begs the question of whether it's actually useful to
    #     keep.
    VDO              => sub { return 1},
    VFARM            => sub { return (_isVFarm() || _isDevVM()) },
  );
  foreach my $key (keys %classMap) {
    if ($classMap{$key}()) {
      _assertMember($key);
    } else {
      _assertNotMember($key);
    }
  }
}

######################################################################
# Assert that host should be a member of a RSVP class.
#
# @param class           the name of the class
##
sub _assertMember {
  my ($class) = @_;
  if (!_isInClass($class)) {
    error("Should be a member of class $class",
          "rsvpclient modify $SHORT_HOSTNAME --add $class");
  }
}

#XXX BEGIN ###########################################################
# we are really confused in regard to what's an OS (RHEL7, RHEL8, etc.)
# and what's a PkgBundle: (ALBIREO, etc.)
######################################################################
# Asserts the a machines is a member of one package bundle class
# (i.e. ALBIREO, etc.)
##
sub _assertMemberPkgBundle {
  my $release = uc(getPkgBundle());
  # XXX not all of these are really OS classes so take out the
  #     real OS classes for now since we deal with them in
  #     _assertMemberOsClass(). Eventually, we'll want something
  #     that asserts a machine is a member of a configuration:
  #       ALBIREO, VDO, PMI, etc
  #     and a member of an OS:
  #       RHEL7, RHEL8, FEDORA35, etc
  my $distFilter = join('|', map {"^$_\$"} @DIST_CLASSES);
  my @osClasses = grep(!/$distFilter/, Permabit::RSVP::listOsClasses());
  _assertMember($release);
  _assertNotMemberOfClasses(grep(!/^$release$/, @osClasses));
}

######################################################################
# Asserts the a machines is a member of OS class
# (i.e. RHEL7, RHEL8, FEDORA35, etc.)
##
sub _assertMemberOsClass {
  my $os = uc(_getOsClass());
  # Check if kernel name end with debug, if it does,
  # we should test if it is in OS+DEBUG class.
  if($kernel =~ /debug$/) {
    $os .= "DEBUG";
  }
  _assertMember($os);
  _assertNotMemberOfClasses(grep(!/^$os$/, @DIST_CLASSES));
}
# XXX END ############################################################

######################################################################
# Asserts the a machines is a member of an ARCH class
# (i.e. AARCH64, PPC64LE, S390X, X86_64)
##
sub _assertMemberArchClass {
  _assertMember($arch);
  _assertNotMemberOfClasses(grep(!/^$arch$/, @ARCH_CLASSES));
}

######################################################################
# Returns the RSVP linux distribution name for this machine's OS.
# XXX make this more generic (i.e. add a new PlatformUtils function
#     that returns the right string).
##
sub _getOsClass {
  # The following is the mapping of Linux distribution names and the
  # function to check for them
  my %versionMap = (
    # The centos8 check would normally be isOotpa but CentOS 8 does not
    # identify itself as Ootpa (though it is) so we use the check for CentOS 8
    # instead.
    centos8   => \&isCentOS8,
    rhel7     => \&isMaipo,
    rhel8     => \&isOotpa,
    rhel9     => \&isPlow,
    fedora27  => \&isTwentySeven,
    fedora28  => \&isTwentyEight,
    fedora29  => \&isTwentyNine,
    fedora30  => \&isThirty,
    fedora31  => \&isThirtyOne,
    fedora32  => \&isThirtyTwo,
    fedora33  => \&isThirtyThree,
    fedora34  => \&isThirtyFour,
    fedora35  => \&isThirtyFive,
    fedora36  => \&isThirtySix,
    fedora37  => \&isThirtySeven,
    fedora38  => \&isThirtyEight,
    fedora39  => \&isThirtyNine,
    fedora40  => \&isForty,
    rawhide   => \&isRawhide,
  );
  # Fedora linux-next kernel can run on any Fedora OS. Check to see if
  # it is running next first before we check other OS.
  if (isFedoraNext()) {
    return "fedoranext";
  }
  # Check and return the version for everything else
  foreach my $key (keys %versionMap) {
    if ($versionMap{$key}()) {
      return $key;
    }
  }
  _die("can't determine OS");
}

######################################################################
# Determines if the host should be running NTP.
##
sub _isNTP {
  return !_isVirtual();
}

######################################################################
# Assert that host should be a member of multiple RSVP classes.
#
# @param classes                 the names of the classes
##
sub _assertMemberOfClasses {
  my (@classesToCheck) = @_;
  foreach my $class (@classesToCheck) {
    _assertMember($class);
  }
}

######################################################################
# Assert that host should be a member of only specified RSVP classes
# and no others
#
# @param requiredClasses        the names of the classes the host should be in
##
sub _assertMemberOfOnly {
  my (@requiredClasses) = @_;
  my @safeClasses = (
    'SMARTFAIL',
  );
  _assertMemberOfClasses(@requiredClasses);
  my @unbelongingClasses;
  foreach my $class (_getRSVPClasses()) {
    if (!grep(/^$class$/, @requiredClasses, @safeClasses)) {
      push (@unbelongingClasses, $class);
    }
  }
  _assertNotMemberOfClasses(@unbelongingClasses);
}

######################################################################
# Assert that host should not be a member of a RSVP class.
#
# @param class           the name of the class
##
sub _assertNotMember {
  my ($class) = @_;
  if (_isInClass($class)) {
    error("Should not be a member of class $class",
          "rsvpclient modify $SHORT_HOSTNAME --del $class");
  }
}

######################################################################
# Assert that host should not be a member of multiple RSVP classes.
#
# @param classes                 the names of the classes
##
sub _assertNotMemberOfClasses {
  my (@classesToCheck) = @_;
  foreach my $class (@classesToCheck) {
    _assertNotMember($class);
  }
}

######################################################################
# Check rsvp class membership for a single class
#
# @param class  name of class to check
#
# @return  true|false        Boolean success indicator.
##
sub _isInClass {
  my ($class)  = @_;
  my @myClasses = _getRSVPClasses();

  return scalar(grep(/^$class$/, @myClasses));
}

######################################################################
# Handle a host with no class info successfully.  The host may
# legitimately have no classes or be in MAINTENANCE or not be in RSVP.
##
sub _getRSVPClasses {
  if (!@rsvpClasses) {
    my $rsvp = Permabit::RSVP->new();
    eval {
      @rsvpClasses = $rsvp->getClassInfo($SHORT_HOSTNAME);
    };
    eval {
      if ($rsvp->isInMaintenance($SHORT_HOSTNAME)) {
        push (@rsvpClasses, 'MAINTENANCE');
      }
    };
  }
  return @rsvpClasses;
}

######################################################################\
# Check for a kernel module.
#
# @param moduleName   the name of the kernel module
##
sub _checkModule {
  my ($moduleName) = @_;
  my $lsmodResult = `lsmod`;
  if ($lsmodResult =~ /$moduleName/ ) {
    error("FOUND module $moduleName", "sudo rmmod $moduleName");
  }
  if (-f '/etc/modules') {
    my $grepResult = `grep "^$moduleName" /etc/modules`;
    if ($grepResult =~ /$moduleName/ ) {
      error("FOUND module $moduleName in startup list",
            "sudo sed -i /^$moduleName/d /etc/modules");
    }
  }
}

######################################################################\
# Check for kernel modules.
##
sub checkModules {
  # lsmod lists the active kernel modules in the correct order for them to be
  # removed.  In particular, "uds" will be listed after "kvdo" and/or
  # "zubenelgenubi".
  my $lsmodResult = `lsmod`;

  foreach my $name ($lsmodResult =~ m/^(\S+)\s+\d+/gm) {
    if (exists($testModules{$name})) {
      _checkModule($name);
    }
  }

  return;
}

######################################################################\
# Recursively follow symlinks until we get to a file.
##
sub readlink_recursive {
  my $file = shift;
  if ( -l $file) {
    return readlink_recursive(readlink($file));
  }
  return $file;
}

######################################################################
# Get the size available in the given partition.  Returns -1 if unable to
# determine available size.
#
# This should be rewritten using Filesys::DiskSpace when it is
# installed
##
sub _getPartitionAvailableSize {
  my ($partition) = @_;
  my $sizeAvailable = -1;
  my $regexp = '^/dev/\S+\s+\d+\s+\d+\s+(\d+)\s+\d+%\s+/.*$';
  open(my $dh, "df -P -k $partition|")
    || _die("Couldn't run df on $partition: $ERRNO");
  while (<$dh>) {
    chomp;
    if (m|$regexp|) {
      $sizeAvailable = $1 * 1024;
    }
  }
  close($dh) || _die("Couldn't run df on $partition: $CHILD_ERROR");
  return $sizeAvailable;
}

######################################################################
# Get the physical size of the given partition.
#
# @param partition The partition to get the physical size of
#
# @return The size of the given partition or -1 if unable to determine it
##
sub _getPartitionSize {
  my ($partition) = @_;

  open(my $partitions, '<', '/proc/partitions');
  while (my $line = <$partitions>) {
    if ($line =~ /\s+\d+\s+\d+\s+(\d+)\s+$partition/) {
      return $1;
    }
  }
  close($partitions);

  return -1;
}

######################################################################
# Get the physical device associated with the given partition
#
# @param volume The volume to get the device for
#
# @return The base device name or nothing if unable to determine it
##
sub _getPartitionDevice {
  my ($volume) = @_;

  my $dfOutput = `df -P $volume`;
  my $farmScratchPath = "/dev/mapper/(" . _generateScratchVGPattern()
                      . ")-scratch";
  # Attempt to get the device name of the volume
  if ($dfOutput =~ m|/dev/([shv]d[a-z]+\d+).*$volume|) {
    return $1;
  } elsif ($dfOutput =~ m#($farmScratchPath)#) {
    # If logical volume, dereference the device mapper link
    return `basename \$(readlink $1)`;
  }
  # For pmifarm, the partition device is /u1
  # and it is /dev/vdb
  if (_isPMIFarm()) {
    return "vdb";
  }
  error("Unable to find partition containing /u1");
  return "none";
}

######################################################################
# Check whether the given file exists, is owned by root, and has write
# permissions.
##
sub _checkRootWritePermissions {
  my ($file) = @_;
  my $stat = stat($file);
  if (defined($stat)) {
    if ($stat->uid != 0) {
      my $user = (getpwuid($stat->uid))[0];
      error("$file is owned by $user, not root");
    }
    if (($stat->mode & 0200) == 0) {
      error("$file is not writable by owner (mode "
            . sprintf("%lo", $stat->mode) . ")");
    }
  } else {
    error("$file does not exist");
    $reboot = 1;
  }
}

######################################################################
# Check whether the given file or directory is both readable and writeable
# by members of $STAFF_GID.
##
sub _checkStaffPermissions {
  my ($file) = @_;
  my $stat = stat($file) || _die("no such file $file");
  my $modeStr = sprintf "%lo", $stat->mode;
  if ($stat->gid == $STAFF_GID) {
    # If group == staff, the file must be group accessible.
    if (($stat->mode & 0060) != 0060) {
      error("$file is not group accessible ($modeStr, ". $stat->mode . ")",
            "chmod g+rw $file");
    }
  } elsif (($stat->mode & 0006) != 0006) {
    # Otherwise, the file must be world accessible.
    error("$file is not world accessible ($modeStr, ". $stat->mode . ")",
          "chmod a+rw $file");
  }
}

######################################################################
# Check whether the given file or directory is both readable and writeable
# by the triage user.
##
sub _checkTriagePermissions {
  my ($file) = @_;
  if ($file =~ /logfile.timestamp$/) {
    # Ignore files that are always manipulated as root
    return;
  }
  my $stat = stat($file) || _die("no such file $file");
  my $modeStr = sprintf "%lo", $stat->mode;
  my $triageUserName = triageUserName();
  my $triageUserUid = triageUserUid();
  if (($stat->uid != $triageUserUid) || !($stat->mode & 0600)) {
    # files must be accessible by triage user
    error("$file is not $triageUserName accessible ($modeStr)",
          "chown $triageUserName $file && chmod o+rw $file");
  }
}

######################################################################
# Check whether a given package starts on boot and kick an error if so
#
# @param  $service  Service which should not start at boot time
##
sub _checkNoStartOnBoot {
  my $service = shift @_;
  my @files = glob("/etc/rc?.d/S??$service");
  if (@files) {
    return $service;
  }
  return;
}

######################################################################
# Return the command to rebuild the given file via
# /permabit/mach/Makefile.
##
sub _rebuildFromMach {
  my ($file, $noVarConf) = (@_, 0);

  if (_isAnsible()) {
    # No fixes available yet for the Ansible-based installations.
    return '';
  }

  my $cmd = '';
  if (! -f "$MACH_DIR/Makefile") {
    my $server = redhatNFSServer();
    $cmd = "mount $server:/vdo_permabit_system_nfs /permabit/system; ";
  }
  $cmd .= "make --always-make -f $MACH_DIR/Makefile";
  $cmd .= $noVarConf ? " $file": " /var/conf/$file";
  return $cmd;
}

######################################################################
# Check if this host is an Albireo PMI machine.
##
sub _isAlbPerf {
  return scalar(grep { $_ eq $SHORT_HOSTNAME } @{albireoPerfHosts()});
}

######################################################################
# Check if this host is a VDO PMI machine.
##
sub _isVDOPerf {
  return scalar(grep { $_ eq $SHORT_HOSTNAME } @{vdoPerfHosts()});
}

######################################################################
# Check if this host is a farm class machine
##
sub _isFarm {
  return _hostInList(
                     'jfarm',
                     'pfarm',
                    )
          || (getScamVar('FARM') eq 'yes');
}

######################################################################
# Check if this machine was installed with Ansible rather than FAI
##
sub _isAnsible {
  return !!getScamVar('ANSIBLE');
}

######################################################################
# Check if this machine is a Red Hat lab machine instead of a Permabit
# lab machine or a local VM
##
sub _isBeaker {
  return !!getScamVar('BEAKER');
}

######################################################################
# Check if this host is a development VM box
##
sub _isDevVM {
  # Includes the condition for Vagrant to identify systems that were created
  # before DEVVM was added as a SCAM variable.
  return (!!getScamVar("DEVVM")) || _isVagrant();
}

######################################################################
# Check if this host is a Vagrant box
##
sub _isVagrant {
  return !!getScamVar('VAGRANT');
}

######################################################################
# Check if this host is a jfarm class machine
##
sub _isJFarm {
  return _hostInList('jfarm');
}

######################################################################
# Check if this host is a pfarm class machine
##
sub _isPFarm {
  return _hostInList('pfarm');
}

######################################################################
# Check if this host is a pfarm class machine
##
sub _isPMIFarm {
  return _hostInList('pmifarm');
}

######################################################################
# Check if this host is a virtual farm class machine
##
sub _isVFarm {
  return _hostInList('vfarm');
}

######################################################################
# Check if this host is a virtual host (VMWare, Xen, QEMU, etc).
##
sub _isVirtual {
  if (_isVFarm() || _isDevVM()) {
    return 1;
  }
  my $detectedVirt = `systemd-detect-virt 2>/dev/null`;
  chomp($detectedVirt);
  # Empty if not installed; "none" if bare metal.
  if ($detectedVirt eq "none") {
    return 0;
  } elsif ($detectedVirt ne "") {
    # kvm, vmware, qemu, ...
    return 1;
  }
  if ($machine eq 'x86_64') {
    my $productName = `sudo dmidecode -s system-product-name 2>/dev/null`;
    chomp($productName);
    if (($productName eq "KVM")
        || ($productName eq "VMware Virtual Platform")
        || ($productName eq "VirtualBox")) {
      return 1;
    }
  }
  return 0;
}

######################################################################
# Check if $HOSTNAME matches any of the patterns in a list.
##
sub _hostInList {
  my @list = @_;
  my $namePattern = "^(" . join('|', @list)  . ")-";
  return ($HOSTNAME =~ /$namePattern/);
}

######################################################################
# Wrapper around die to print proper failure message
##
sub _die {
  print "FAILURE\n";
  croak(@_);
}

######################################################################
# Check for write access to /u1 and /permabit/not-backed-up
##
sub checkCanWrite {
  my @dirsToCheck = ("/u1", "/permabit/not-backed-up/tmp", "/tmp");
  my $fileName;
  foreach my $dir (@dirsToCheck) {
    # Check to see if the tmp directory exists
    if (!-d $dir) {
      error("$dir does not exist or cannot be accessed.");
      next;
    }
    # Make sure we can write files into the path
    $fileName="$dir/checkServer.checkCanWrite.$HOSTNAME.$$";
    open(my $fh, ">", "$fileName")
      or error("Cannot write to $fileName: $ERRNO");
    close($fh);
    unlink($fileName) || error("Cannot remove $fileName: $ERRNO");
  }
}

######################################################################
# Fix the sudoers file if it's out of date.
##
sub checkSudoers {
  my $sudoers      = "sudoers";
  my $nfsSudoers   = "$MACH_DIR/files/$sudoers";
  my $localSudoers = "/etc/$sudoers";

  if (_isAnsible()) {
    # We install a couple of sudoers files for specific users; it's
    # not consistent across different setups.
    # XXX Skip checking, for now.
  } else {
    if ((! -f $localSudoers) || (! -f $nfsSudoers)
        || (-M $localSudoers > -M $nfsSudoers)) {
      # We push the fix onto the @fixes array without calling error()
      # because we don't want the sudoers file to be an error condition.
      push(@fixes, _rebuildFromMach($sudoers));
    }
  }
}

######################################################################
# Check for the required nfs mounts.
##
sub checkNFSMounts {
  # Prepare the list of mounts that are specific to the server that is being
  # checked
  my %uniqueMounts = ();
  my $server = redhatNFSServer();
  my %nfsInternalMounts =
    Permabit::Internals::CheckServer::Host->new()->getPermabitMounts();

  if (_isDevVM() || _isBeaker()) {
    # NFS server names will vary.
    %uniqueMounts = (
       "/permabit/not-backed-up"  => "*:/permabit/not-backed-up",
                    );
    if (defined($server) && _isBeaker() && _isFarm()) {
      $uniqueMounts{"/permabit/datasets"}
        = "$server:/vdo_permabit_datasets_nfs";
    }
  } else {
    %uniqueMounts = ();
    if (defined($server)) {
      for my $permabitMount (keys (%nfsInternalMounts)) {
	$uniqueMounts{$permabitMount} =
	  "$server:$nfsInternalMounts{$permabitMount}";
      }
    }
  }
  # Check the mounts and report the errors that are returned
  my $errors = _checkMounts(%uniqueMounts);
  if ($errors) {
    error($errors, _rebuildFromMach("fstab"));
    $reboot = 1;
  }
}

######################################################################
# Check the mounts that were provided, if there is an error note it,
# and return the list of all error encountered.
##
sub _checkMounts {
  my %mounts = @_;
  my $pbitMounts=`mount | grep -F /permabit`;
  my $errors = "";
  foreach my $point (keys %mounts) {
    my ($server, $share) = split(/:/, $mounts{$point});
    if ($server eq "*") {
      if ($pbitMounts !~ m|^[^:]+:$share/? on $point .*\)$|m) {
        $errors .= "Did not find mount of $mounts{$point} on $point\n";
      }
    } else {
      my $addr = hostToIP($server);
      if ($pbitMounts !~ m|^[^:]+:$share/? on $point .*,addr=$addr.*\)$|m) {
        $errors .= "Did not find mount of $mounts{$point} "
          . "on $point with addr $addr\n";
      }
    }
  }
  return $errors;
}

######################################################################
# Check for the required nfs mounts.
##
sub checkFstab {
  my %mountPoints;
  open(my $fh, '<', '/etc/fstab') || _die("Can't open fstab: $ERRNO");
  while (<$fh>) {
    if (/^\s*#/ || /^\s*$/) {
      next;
    }

    my (undef, $mp) = split(/\s+/);
    if ($mp !~ m|^/|) {
      next;
    }
    if (!exists($mountPoints{$mp})) {
      $mountPoints{$mp} = 0;
    } else {
      ++$mountPoints{$mp};
    }
  }
  close($fh) || _die("Cannot close fstab: $ERRNO");
  my @dups = grep {if ($mountPoints{$_}) { $_; }} keys(%mountPoints);
  if (my @dups = grep {if ($mountPoints{$_}) { $_; }} keys(%mountPoints)) {
    error("/etc/fstab shouldn't have any duplicate mountpoints.\n"
          . "\tThe following duplicates were found: @dups",
          _rebuildFromMach("fstab"));
  }
}

######################################################################
# Check that the ssh key matches what's in the ssh_known_hosts file
##
sub checkSSHkey {
  if (!$SHORT_HOSTNAME) {
    _die("I don't know what host I'm on");
  }

  if (-x "/usr/bin/ssh-vulnkey") {
    my $vulnkey = `sudo /usr/bin/ssh-vulnkey /etc/ssh/ssh_host_dsa_key`;
    if ($vulnkey =~ m/COMPROMISED/) {
      error("Compromised ssh key",
            "rm /etc/ssh/ssh_host\* ; dpkg-reconfigure openssh-server");
    }
  }

  my $SSH = "$OPS_DIR/ssh/hostkeys/$SHORT_HOSTNAME";
  my $ARCHIVED_SSH_KEY = "$SSH/ssh_host_rsa_key.gpg";

  #get an array of all the public key files
  my @keyFiles = glob("/etc/ssh/ssh_host_*.pub");
  #if we don't find any keys, abort
  if (scalar(@keyFiles) == 0) {
    _die("Can't find any ssh-keys on this machine");
  }

  #open ssh_known_hosts file and grep out entries for this host
  my $sh;
  if (!open($sh, "$SSH_KNOWN_HOSTS")) {
    error("open $SSH_KNOWN_HOSTS: $ERRNO", $FIXSSH);
    return;
  }
  my @sshKnownHosts = <$sh>;
  close($sh) || _die("Cannot close $SSH_KNOWN_HOSTS: $ERRNO");
  my @keyEntries = grep { /^$SHORT_HOSTNAME,/ } @sshKnownHosts;

  #if keys are not archived we need to run ssh_archive
  if (! -e $ARCHIVED_SSH_KEY) {
    error("ssh key is not archived. Please run: "
         . "\n $SSH_ARCHIVE $SHORT_HOSTNAME");
    return;
  }

  #put the contents of all the keyfiles into an array
  my @machineKeys;
  foreach my $keyFile (@keyFiles) {
    open(my $fh, $keyFile) || _die("Can't open $keyFile: $ERRNO");
    my @keyContents = <$fh>;
    push(@machineKeys, @keyContents);
    close($fh) || _die("Cannot close $keyFile: $ERRNO");
  }

  #Trim off the first item of the ssh_known_hosts entries
  foreach my $currentKey (@keyEntries) {
   $currentKey =~ s/^\S+\s+//;
  }
  #Trim off the last item of the key file entries
  foreach my $currentKey (@machineKeys) {
   $currentKey =~ s/\s+\S+$//;
  }

  #Build a hash to count the number of matches
  my @differences;
  my %count;
  foreach my $element (@machineKeys, @keyEntries) {
    $count{$element}++;
  }
  foreach my $element (keys %count) {
    if ($count{$element} != 2) {
      push (@differences,$element);
    }
  }

  #if we couldn't find a match for all of the keys on the machine,
  #then we must run fixssh
  if (scalar(@differences) != 0) {
    my $errorString  = "The wrong ssh-keys are on this machine.";
    error($errorString, "$FIXSSH");
  }
}

######################################################################
# Check that DEBUG is not turned on in the lab.  This caused major
# problems see @53529, RT/36032.
##
sub checkSSHDconfig {
  my $sshdConfig = "/etc/ssh/sshd_config";
  open (my $fh, $sshdConfig ) || _die("Can't open $sshdConfig: $ERRNO");
  my @lines = grep { /LogLevel.*INFO/ } <$fh>;
  if (scalar(@lines) != 1) {
    error("LogLevel not set to INFO in /etc/ssh/sshd_config",
          _rebuildFromMach("sshd_config"));
  }
}

######################################################################
# Check that kernel logs are not too large and look for problems in them.
#   under --fix:
#     - If possible, use logrotate to rotate large kern.log and then
#       rename it to kern.large.log.
#     - Rename large kern.log.* to kern.large.log* so that future
#       runs of checkServer will not try to grep them.
##
sub checkKernLog {
  # Messages from early in the reboot sequence
  my $bootStrings = join("|",
                         "/proc/kmsg started",      # do not know
                         "000000] Linux version ",  # old RHEL7 or Fedora
                         " Initializing cgroup subsys cpuset"); # Red Hat
  # Messages that indicate a problem in the running kernel.  Be careful not to
  # include a single word in this list (like "OOPS").  An arbitrary sequence of
  # letters can be embedded in a UUID.  Note that all of these strings include
  # at least one space.
  my $bugStrings = join("|",
                        " BUG",
                        "Busy inodes after unmount",
                        "general protection fault",
                        '[kv]malloc memory used \(\S+ bytes in \S+ blocks\)'
                        . " is returned to the kernel");
  my $egrepStr = "$bootStrings|$bugStrings";
  my $foundLatestStart = 0;
  my @errors = ();

  my $kernLog = '/var/log/kern.log';
  my $kernLogSize = -s $kernLog;
  if ($kernLogSize > $MAX_KERN_LOG_SIZE) {
    my $cmd = 'logrotate /etc/logrotate.d/kern';
    $cmd .= ' && mv /var/log/kern.log.1 /var/log/kern.large.log';
    error("$kernLog is too large ($kernLogSize bytes)", $cmd);
  }

  if (!open(LOG, "sudo journalctl -k -o short-monotonic 2>/dev/null |")) {
    error("Failed to run journalctl\n");
  }
  while (my $line = <LOG>) {
    if ($line =~ m/$bugStrings/) {
      push(@errors, $line);
    }
  }
  close(LOG);
  if (@errors) {
    error("This machine is unstable: Kernel bug noted:\n"
          . join("\n", @errors));
    $reboot = 1;
  }
}

######################################################################
# Check that the machine has no logical volumes set up.
##
sub checkLVM {
  # Start by checking to make sure we can run vgscan and that it isn't in a
  # state that would cause things to hang.
  my $timeout = 30;
  my @outputLines;
  eval {
    local $SIG{ALRM} = sub { die "alarm\n" };
    alarm $timeout;
    @outputLines = `vgscan 2>&1`;
    alarm 0;
  };
  if ($EVAL_ERROR) {
    if ($EVAL_ERROR eq "alarm\n") {
      _die("vgscan failed to return in $timeout seconds.");
    }
    _die("Unable to run vgscan.");
  }

  # Any devices matching the scratch pattern are part of the permanent
  # configuration.
  my $vgPattern = _generateScratchVGPattern();

  # Get the tree of block devices with name and type, forced to ASCII
  # representation.
  open(my $fh, "env LANG=C lsblk -noheadings -o NAME,TYPE |")
    || _die("couldn't run lsblk; OS_ERROR = \"$OS_ERROR\"");

  my @volumes = ();
  foreach my $line (<$fh>) {
    chomp $line;
    if ($line =~ /^\s*([`|-]-)*(?<name>([\w.-])+)\s+(?<type>\w+)$/) {
      my $device = {name => $+{name}, type => $+{type}};
      if ($device->{name} !~ /$vgPattern/) {
        unshift(@volumes, $device);
      } else {
        $log->debug("Scratch device '$device->{name}' ignored");
      }
    }
  }

  close($fh) || _die("couldn't run lsblk; $CHILD_ERROR");

  foreach my $volume (@volumes) {
    if ($volume->{type} eq "lvm") {
      my $split = `dmsetup splitname --noheadings $volume->{name}`;
      my ($vg,$lv) = split(/:/, $split);
      # Remove the lv, and if it's the last lv, remove the vg too
      my $lvremove = "sudo lvremove --force $vg/$lv;\n"
        . "lv_count=`sudo vgs -o lv_count --noheadings $vg`;\n"
          . "[ \"\$lv_count\" != 0 ] || sudo vgremove --force $vg";
      error("Found LVM logical volume $lv", $lvremove);
    } elsif ($volume->{type} eq "dm" or $volume->{type} eq "vdo") {
      my $name = $volume->{name};
      error("Found device mapper target $name",
            "sudo dmsetup remove $name || sudo dmsetup remove --force $name");
    }
  }

  # Get a list of volume groups for removal in case any are left after
  # the initial pass of lvm fixes.
  open($fh, "sudo vgs --noheadings -o vg_name 2>/dev/null |")
    || _die("couldn't run vgs; OS_ERROR = \"$OS_ERROR\"");
  @outputLines = <$fh>;
  close($fh) || _die("couldn't run vgs; $CHILD_ERROR");
  map { chomp; s/^\s*|\s*$//g; } @outputLines;
  @outputLines = grep(!/^($vgPattern)/, @outputLines);
  foreach my $vg (@outputLines) {
    error("found LVM volume group $vg",
          "sudo vgs $vg && sudo vgremove --force $vg");
  }

  # Get a list of physical volumes for removal in case any are left
  # after the initial pass of lvm fixes.
  open($fh, "sudo pvs --noheadings -o pv_name,vg_name 2>/dev/null |")
    || _die("couldn't run pvs; OS_ERROR = \"$OS_ERROR\"");
  @outputLines = <$fh>;
  close($fh) || _die("couldn't run pvs; $CHILD_ERROR");
  my %physicalVolumes = map {
    my @words = split(" ", $_);
    $words[0] => ($words[1] // "")
  } @outputLines;
  @volumes = keys(%physicalVolumes);

  # Remove any devices associated with standard volume groups.
  @volumes = grep { $physicalVolumes{$_} !~ /^($vgPattern)$/ } @volumes;

  if (@volumes) {
    error("found LVM physical volumes @volumes",
          "sudo pvremove -f @volumes && vgscan");
  }

  # Check for warnings of orphaned physical volumes since their existence
  # breaks the 'does a volume already exist?' check in VDO manager (VDO-4361).
  open($fh, "sudo pvs 2>&1 >/dev/null |")
    || _die("couldn't run pvs; OS_ERROR = \"$OS_ERROR\"");
  @outputLines = <$fh>;
  close($fh) || _die("couldn't run pvs; $CHILD_ERROR");
  @outputLines = grep(/WARNING: .* not found or rejected by a filter/,
                      @outputLines);
  if (@outputLines) {
    error("found orphaned physical volume",
          "sudo pvscan --cache");
  }
}

######################################################################
# Check the global LVM configuration.
##
sub checkLVMConf {
  if (-f $LVM_CONF) {
    open(my $lvmConf, $LVM_CONF)
      || _die("Couldn't open $LVM_CONF: $ERRNO");
    my @lines = grep { /verbose\s*=\s*[123]/ } <$lvmConf>;
    close($lvmConf) || _die("Couldn't close $LVM_CONF: $ERRNO");
    if (@lines) {
      error("lvm configured with bad verbose level",
            "sed -i 's/verbose = [123]/verbose = 0/' $LVM_CONF");
    }
  }
}

######################################################################
# Check that there are no dkms packages installed
##
sub checkDKMS {
  foreach my $moduleName (keys(%testModules)) {
    open(my $fh, "dkms status -m $moduleName 2>&1 |")
      || _die("couldn't run dkms; OS_ERROR = \"$OS_ERROR\"");
    foreach my $line (<$fh>) {
      chomp($line);
      if ($line !~ /^$moduleName[,\/]\s*(\S+)[,:]/) {
        _die("dkms output unexpected: $line");
      }
      error("found $moduleName DKMS package ($1)",
            "dkms remove -m $moduleName -v $1 --all");
    }
    close($fh) || _die("couldn't run dkms; $CHILD_ERROR");

    # Sometimes DKMS fails to completely cleanup the module. If
    # modinfo exits with a non-zero status then that means vdo
    # isn't installed.
    open($fh, "modinfo $moduleName 2>/dev/null|")
      || _die("couldn't run modinfo; OS_ERROR = \"$OS_ERROR\"");
    foreach my $line (<$fh>) {
      chomp($line);
      if ($line =~ /^filename:\s+(\S+)/) {
        error("found $moduleName installed ($1)", "rm -f $1 && depmod");
      }
    }
    close($fh);

    # Make sure we haven't left unpacked sources lying around,
    # including older versions.
    foreach my $dir (glob("/usr/src/$moduleName-*")) {
      if (-d $dir) {
        error("$dir exists", "rm -rf $dir");
      }
    }
  }
}

######################################################################
# Determine if physical memory was limited at boot time
#
# @return current physical memory if it was limited at boot time
##
sub _isMemoryLimited {
  open(my $fh, '<', '/proc/cmdline')
    || _die("can't get kernel command line: $ERRNO");
  my $cmdline = <$fh>;
  close($fh) || _die("couldn't close /proc/cmdline: $ERRNO");
  return ($cmdline =~ m/mem=(\d+\w)/) ? $1 : undef;
}

######################################################################
# Generate a regex compatible pattern containing the possible VG names
# for an [al]farm's scratch volume for testing.
#
# @return the pattern containing the possible VG names
##
sub _generateScratchVGPattern {
  my @names;

  # Get the unique scratch VG names.
  push(@names, _getUniqueScratchVGNames());

  # Add the other possible names for the scratch VG name
  push(@names, 'scratch', 'vg_xvd[a-z]2', _generateSystemVGPattern());

  # Return the list of names in a regex compatible format
  return join('|', @names);
}

######################################################################
# For every visible entry in /sys/class/net (except for 'lo') that resolves
# to a directory containing a file named 'address' we include the MAC address
# (sans :'s) from that file as an acceptable VG name.
#
# @return array of formatted MAC addresses
##
sub _getUniqueScratchVGNames {
  # Set the default return value to an empty string in case we can't find a mac
  # address to use
  my @scratchVGs = ();

  my @files = grep { !/.*\/lo$/ } glob('/sys/class/net/*');
  @files = map { "$_/address" } @files;
  @files = grep { -e $_ } @files;
  for my $file (@files) {
    open(my $ethMAC, '<', $file);
    my $scratchVG;
    ($scratchVG) = <$ethMAC>;
    close($ethMAC);
    $scratchVG =~ s/://g;
    chomp($scratchVG);
    push(@scratchVGs, $scratchVG);
  }

  return @scratchVGs;
}

######################################################################
# Generate a regex compatible pattern containing the possible VG names
# for a farm's OS volumes (root, home, etc).
#
# @return the pattern containing the possible VG names
##
sub _generateSystemVGPattern {
  my @names;

  # CentOS/RHEL 7.5 and Fedora configurations seem to incorporate the
  # distro name and host name.
  push(@names, 'cl_[a-z0-9_-]*', 'rhel_[a-z0-9_-]*', 'fedora_[a-z0-9_-]*');
  # Some virtualization products (e.g., Parallels) don't incorporate the
  # distro and host names for CentOS/RHEL.  If this is a virtual machine allow
  # simply 'cl' and 'rhel' as options.
  if (_isVirtual()) {
    push(@names, 'cl', 'rhel');
  }

  # Return the list of names in a regex compatible format
  return join('|', @names);
}

######################################################################
# Get the amount of memory.
#
# @return value of memory limit set in the config file, or undef if not set
##
sub _getMemorySetting {
  my $setSize = "";
  my $SEDCMD = "sed 's/#.*\\\$//'";

  # version can only be 1 or 2 right now
  if (! -r "/etc/default/grub") {
    # May be S/390. On S/390 Fedora 28, /boot/grub2 exists but is
    # empty so we follow the grub v2 path.
    #
    # TODO Update this function for zipl.conf when we start making
    # use of it.
    return undef;
  }
  my $CATCMD = "cat /etc/default/grub";
  # Assumes that there is only 1 occurance of GRUB_CMDLINE_LINUX
  $setSize = `$CATCMD | $SEDCMD | grep "GRUB_CMDLINE_LINUX=.*mem="`;

  return ($setSize =~ m/mem=(\d+\w)/) ? $1 : undef;
}

######################################################################
# Get the amount of memory.
#
# @return amount of memory (in kB)
##
sub _getMemory {
  my $size = `grep MemTotal /proc/meminfo`;
  $size =~ s/\D*(\d+).*/$1/;
  chomp($size);
  return $size;
}

######################################################################
# Check that we have a crashkernel= value in the kernel commandline
##
sub checkKDumpConfig {
  my $crashParam;
  my $fixStr;
  my $grepString;
  my $grubConfig;

  my $grub2DefaultStart = "GRUB_CMDLINE_LINUX_DEFAULT";

  # Set the expected crashkernel values based on distro
  if (isMaipo() || (isOotpa() || isCentOS8())) {
    $crashParam = 'crashkernel=auto';
    $grub2DefaultStart = 'GRUB_CMDLINE_LINUX';
  } else {
    # If we didn't set crashParam, then we probably don't have kdump
    # configured for the given distro.  So we should just return for now.
    return;
  }

  # Detect grub version and assemble the checks as necessary
  my $sedCmd = "sudo sed -r -i";
  $grubConfig = "/etc/default/grub";
  $grepString = "$grub2DefaultStart=\".*$crashParam.*\"";
  $fixStr = "$sedCmd 's/$grub2DefaultStart\".*\"/"
                     . "$grub2DefaultStart\"$crashParam\"/\' "
                     . $grubConfig;

  # Read grub config and check to see if it is valid
  open(my $grubFile, '-|', "sudo cat $grubConfig");
  my @configData = <$grubFile>;
  close($grubFile);
  if (grep(/$grepString/, @configData)) {
    return;
  }

  error("$crashParam not found in grub config.", $fixStr);
  $reboot = 1;
}

######################################################################
# Check that we have kexec loaded
##
sub checkKExecLoaded {
  # Read grub config and check to see if it is valid
  open(my $grubFile, '-|', "cat /sys/kernel/kexec_crash_loaded");
  my @configData = <$grubFile>;
  close($grubFile);
  if (grep(/1/, @configData)) {
    return;
  }

  error("kexec not loaded, KDump not configured properly.");
  $reboot = 1;
}

######################################################################
# Check that it has more than minimal amount of memory, and check
# that active memory and boot settings are unrestricted or set to 6GB.
##
sub checkMemory {
  my $actualMem = _getMemory();
  if ($actualMem < $MIN_MEMORY) {
    error("All machines are expected to have at least $MIN_MEMORY kB"
          . ", actual: $actualMem kB");
  }

  my $limitedMemory = _isMemoryLimited();
  if ($limitedMemory && lc $limitedMemory ne "7168m") {
    error("Current memory value is limited and not 7168M (6GB)");
  }

  my $setMemory = _getMemorySetting();
  if ($setMemory && lc $setMemory ne "7168m") {
    my $fixStr;

    # right now grub version will be either 1 or 2
    my $GRUBFILE = "/etc/default/grub";
    $fixStr = -f "$GRUBFILE.bak" ?
              "mv $GRUBFILE.bak $GRUBFILE && update-grub" : undef;

    error("Machines are expected to boot with no memory restrictions"
          . " or with a setting of 7168M (6GB)",
          $fixStr);
    $reboot = 1;
  }
}

########################################################################
# Checks to see if SMART is enabled for the drives examined by
# Permabit::RemoteMachine::waitForDiskSelfTests.
##
sub checkSmartEnabled {
  foreach my $dev (`cat /proc/partitions` =~ m/ ([hs]d[a-z])$/mg) {
    my $smartOut = `sudo smartctl -i /dev/$dev`;
    if ($CHILD_ERROR) {
      _die("unable to run smartctl: $CHILD_ERROR");
    }
    if ($smartOut =~ m/Device supports SMART and is Enabled/) {
      next;
    } elsif ($smartOut =~ m/SMART support is:\s+Enabled/) {
      next;
    } elsif ($smartOut =~ m/Device does not support SMART/) {
      next;
    } elsif ($smartOut
      =~ m/SMART support is:\s+Unavailable - device lacks SMART capability./) {
      next;
    } elsif ($smartOut =~ m/SMART support is:\s+Disabled/) {
      error("SMART support is: Disabled on /dev/$dev",
            "sudo smartctl -s on /dev/$dev");
    } else {
      error("Nonsense output from smartctl on /dev/$dev");
    }
  }
}

########################################################################
# Clean up the Python installation after some VDO testing.
##
sub checkPythonHacks {
  my $badPythonModule = "vdoInstrumentation";
  my @dirs = split(/\s+/,
                   `python3 -c 'import sys; print(" ".join(sys.path))'`);
  foreach my $dir (@dirs) {
    foreach my $suffix ("py", "pyc") {
      my $badFile = "$dir/$badPythonModule.$suffix";
      if (-e $badFile) {
        error("found Python module $badFile", "rm $badFile");
      }
    }
  }
}

########################################################################
# Check for ISCSI targets set up by Permabit::BlockDevice::ISCSI.
##
sub checkISCSITarget {
  my @targets = ();
  my @fixes = ();
  foreach my $line (`sudo targetcli /iscsi ls 2>/dev/null`) {
    if ($line =~ /Targets: 0\]/) {
      last;
    }

    if ($line =~ /^  o- (iqn\S+)/) {
      my $target = $1;
      push(@targets, $target);
      push(@fixes, "targetcli /iscsi delete $target");
    }
  }

  my $report;
  if (@targets) {
    $report = join("\n  ", "found iscsi targets:", @targets);
  }

  my @backstores = ();
  foreach my $line (`sudo targetcli /backstores/block ls 2>/dev/null`) {
    if ($line =~ /Storage Objects: 0\]/) {
      if (@targets) {
        error($report, join('; ', @fixes));
      }

      return;
    }

    if ($line =~ /^  o- (\S+)/) {
      my $backstore = $1;
      push(@backstores, $backstore);
      push(@fixes, "targetcli /backstores/block delete $backstore");
    }
  }

  $report = (defined($report)
             ? "$report\nwith backstores:" : "found iscsi backstores:");
  error(join("\n  ", $report, @backstores), join('; ', @fixes));
}

########################################################################
# Check for ISCSI initiators set up by Permabit::BlockDevice::ISCSI.
##
sub checkISCSIInitiator {
  my @mounts = ();
  foreach my $mount (`sudo iscsiadm -m session 2>/dev/null`) {
    if ($mount =~ /(iqn.2017-07.com.permabit.block-device\S+)/) {
      push(@mounts, $1);
    }
  }

  if (@mounts) {
    error(join("\n  ", 'Found left-over ISCSI mounts:', @mounts),
          join('; ', map({ $_ = "iscsiadm -m node -T $_ -u" } @mounts)));
  }

  my @portals = ();
  foreach my $portal (`sudo iscsiadm -m node 2>/dev/null`) {
    if ($portal =~ /^(\S+),\d+ iqn.2017-07.com.permabit.block-device\S+/) {
      push(@portals, $1);
    }
  }

  if (@portals) {
    error(join("\n  ", 'Found left-over ISCSI discovery targets:', @portals),
          join('; ', map({ $_ = "sudo iscsiadm -m node -o delete -p $_" }
                         @portals)));
  }
}

########################################################################
# Make sure we can identify the test storage device on this machine.
#
# N.B.: Make sure this stays in sync with the code in
# Permabit::LabUtils::getTestBlockDeviceNames!
##
sub checkTestStorageDevice {
  my $gotTestDevice = 0;
  my @testDevices = (
                     "/dev/vdo_scratch",
                     "/dev/vdo_scratchdev_*",
                     "/dev/md0",
                     "/dev/xvda2",
                     "/dev/sda8"
                    );

  if (_isPMIFarm()) {
    my @pmiScratchDevices = glob("/dev/vdo_scratchdev_vd*");
    if (!@pmiScratchDevices) {
      error("unable to locate test storage device");
      return;
    }
    push(@testDevices, @pmiScratchDevices);
  }
  my $megaraid = getScamVar("MEGARAID");
  if ($megaraid) {
    chomp($megaraid);
    unshift(@testDevices, "$megaraid-part1");
  }
  foreach my $device (@testDevices) {
    if (-b $device) {
      return;
    }
  }
  # no fix available
  error("unable to locate test storage device");
}
