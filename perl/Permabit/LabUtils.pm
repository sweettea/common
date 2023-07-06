##
# Utility functions for manipulating Linux Kernels
#
# $Id$
##
package Permabit::LabUtils;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess croak);
use English qw(-no_match_vars);
use List::Util qw(max);
use Log::Log4perl;
use Permabit::Assertions qw(
  assertLENumeric
  assertLTNumeric
  assertMinArgs
  assertMinMaxArgs
  assertNumArgs
  assertTrue
  assertType
);
use Permabit::Constants;
use Permabit::SystemUtils qw(
  assertQuietCommand
  athinfo
  runCommand
  runQuietCommand
  runSystemCommand
);
use Permabit::LabUtils::Implementation;
use Permabit::Utils qw(parseBytes retryUntilTimeout timeToText);
use Scalar::Util qw(blessed);
use Time::HiRes qw(time);

use base qw(Exporter);

our @EXPORT_OK = qw (
  emergencyPowerOff
  emergencyRestart
  fixNextBootDevice
  getPowerStatus
  getSystemUptime
  getTestBlockDeviceName
  getTestBlockDeviceNames
  getTotalRAM
  isOffline
  isVirtualMachine
  powerOff
  powerOn
  rebootMachines
  setHungTaskTimeout
  waitForMachines

  _machineClass
);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

our $VERSION = 1.0;
our $MACHINE_CLASSES;
our $IMPLEMENTATION;

############################################################################
# Return the instance which provides the Configured controlled functionality.
#
# @return the Configured functional instance
##
sub _getImplementation {
  if (!defined($IMPLEMENTATION)) {
    $IMPLEMENTATION = Permabit::LabUtils::Implementation->new();
  }

  return $IMPLEMENTATION;
}

############################################################################
# Initialize, if necessary, the array reference to the Configured array of
# machine classes and return it.
#
# @return reference to the Configured array of machine classes
##
sub _supportedMachineClasses {
  if (!defined($MACHINE_CLASSES)) {
    # The classes are listed such that the base (most generic) class is last.
    # Reverse the ordering in order to load the base class first.
    my @machineClasses = reverse(@{_getImplementation()->{machineClasses}});
    foreach my $classInfo (@machineClasses) {
      my $class = $classInfo->{class};
      my $file = $classInfo->{file};
      if (!defined($file)) {
        eval("use $class");
      } else {
        eval("require '$file'; import $class");
        if ($EVAL_ERROR) {
          die($EVAL_ERROR);
        }
      }
      push(@{$MACHINE_CLASSES}, $class);
    }
  }
  return $MACHINE_CLASSES;
}

############################################################################
# Convenience method returning the list of FQDN suffixes we use to determine
# acceptability of the FQDN as a virtual machine.
#
# @return reference to acceptable FQDN suffixes
##
sub _virtualMachineFQDNSuffixes {
  return _getImplementation()->{virtualMachine}->{name}->{fqdnSuffixes};
}

############################################################################
# Do an emergency restart on a set of machines.  Does not do a clean
# shutdown.
#
# @param hostnames  Hostnames of the machines
##
sub emergencyRestart {
  my (@hostnames) = assertMinArgs(1, @_);
  $log->info("Emergency Restart " . join(",", @hostnames));
  _restartMachinesAndWait("emergencyRestart", \@hostnames);
  $log->info("Emergency Restart Complete " . join(",", @hostnames));
}

############################################################################
# Do an emergency restart on a set of machines.  Does not do a clean
# shutdown.
#
# @param hostnames  Hostnames of the machines
##
sub emergencyPowerOff {
  my @hostnames = assertMinArgs(1, @_);
  $log->info("Emergency powering off " . join(",", @hostnames));
  my @labMachines = map { _makeLabMachine($_) } @hostnames;
  map { $_->emergencyPowerOff() } @labMachines;
  my $stopTime = time();
  # We should probably have a separate, shorter timeout for this,
  # since we don't need the node to go through POST and boot-up
  # sequences, but it only really matters if we're failing.
  my $timeout = max(map { $_->{restartTimeout} } @labMachines);
  for my $hostname (@hostnames) {
    my $timeRemaining = $stopTime + $timeout - time();
    _waitUntilOffline($hostname, $timeRemaining);
  }
  $log->info("Emergency Power-off complete " . join(",", @hostnames));
}

############################################################################
# Test whether a host is offline, by pinging it.
#
# @param host    The name of the host
#
# @return true iff the host fails to respond to ping
##
sub isOffline {
  my ($host) = assertNumArgs(1, @_);
  my $result = runSystemCommand("ping -q -c 2 $host");
  if ($result->{stdout} =~ /packets transmitted, 0 received/) {
    return 1
  } else {
    return 0
  }
}

############################################################################
# Wait until a host stops responding to the network.
#
# @param host      The host to probe
# @param timeout   Maximum time to wait
##
sub _waitUntilOffline {
  my ($host, $timeout) = assertNumArgs(2, @_);
  retryUntilTimeout(sub { isOffline($host); }, "$host still not shut down",
                    $timeout);
}

############################################################################
# Turn off power (physical or virtual) to the indicated hosts. Attempt
# to shut them down cleanly.
#
# @param hostnames   The names of the hosts to switch off
##
sub powerOff {
  my @hostnames = assertMinArgs(1, @_);
  $log->info("Powering off " . join(",", @hostnames));
  my @labMachines = map { _makeLabMachine($_) } @hostnames;
  map { $_->powerOff() } @labMachines;
  my $stopTime = time();
  my $timeout = max(map { $_->{restartTimeout} } @labMachines);
  for my $hostname (@hostnames) {
    my $timeRemaining = $stopTime + $timeout - time();
    _waitUntilOffline($hostname, $timeRemaining);
  }
  $log->info("Power-off complete " . join(",", @hostnames));
}

############################################################################
# Turn on power (physical or virtual) to the indicated hosts.
#
# This can only work for IPMI or virtual hosts.
#
# @param hostnames   The names of the hosts to switch on
##
sub powerOn {
  my @hostnames = assertMinArgs(1, @_);
  $log->info("Powering on " . join(",", @hostnames));
  _restartMachinesAndWait("powerOn", \@hostnames);
  $log->info("Power-on complete " . join(",", @hostnames));
}

############################################################################
# Check the status of power to the indicated machine.
#
# @param host   The name of the machine to check
#
# @return   1 if power is on, 0 if power is off
#
# @croaks   if the power state cannot be determined
##
sub getPowerStatus {
  my ($host) = assertNumArgs(1, @_);
  my $labMachine = _makeLabMachine($host);
  return $labMachine->getPowerStatus();
}

############################################################################
# Retrieve a machine's uptime.
#
# @param host   The name of the machine to check
#
# @return   the machine's uptime in seconds (fractional), or 0 if we
#           can't contact it
##
sub getSystemUptime {
  my ($host) = assertNumArgs(1, @_);

  my $labMachine = _makeLabMachine($host);
  chomp(my $uptime = $labMachine->uptime());
  if ($uptime eq "") {
    return 0;
  } else {
    return $uptime;
  }
}

#############################################################################
# Get the name of a scratch block device for a test to use.
#
# @param machine  The host Permabit::RemoteMachine
#
# @return the full name of the device.
##
sub getTestBlockDeviceName {
  my ($machine) = assertNumArgs(1, @_);
  return getTestBlockDeviceNames($machine)->[0];
}

#############################################################################
# Get the name of the scratch block devices for a test to use.
#
# @param machine  The host Permabit::RemoteMachine
#
# @return array ref of test device names (full path)
##
sub getTestBlockDeviceNames {
  my ($machine) = assertNumArgs(1, @_);
  assertType("Permabit::RemoteMachine", $machine);
  # Just ask the host which of a standard list of devices exists on the system.
  # Use the first group of devices in the list that we actually find.  Optimize
  # this query by sending just a single command to the remote host.
  #
  # The list of devices is:
  #   1 - partition #1 on a Megaraid controller
  #   2 - /dev/vdo_scratch
  #   3 - /dev/vdo_scratchdev_* (raid setup)
  #   4 - /dev/md0
  #   5 - /dev/xvda2
  #   6 - /dev/sda8
  #
  # N.B.: Keep this in sync with the code in checkServer.pl's check
  # that we can find the test devices!
  #
  my $code = <<'EOF';
for D in "`/sbin/scam MEGARAID`-part1" "/dev/vdo_scratch" "/dev/vdo_scratchdev_*" "/dev/md0" "/dev/xvda2" "/dev/sda8";
do
  F=0;
  for E in $D;
  do
    if test -b $E;
    then
      echo $E;
      F=1;
    fi;
  done;
  if test $F -eq 1;
  then
    break;
  fi;
done;
EOF

  $machine->runSystemCmd($code);
  my @devices = split(/\s+/, $machine->getStdout());
  assertLTNumeric(0, scalar(@devices));
  return \@devices;
}

############################################################################
# Returns the total bytes of RAM on the given host.
#
# @param host  Host name
#
# @return the total number of bytes of RAM
##
sub getTotalRAM {
  my ($host) = assertNumArgs(1, @_);

  my $result = assertQuietCommand($host, "cat /proc/meminfo | grep MemTotal:");
  $result->{stdout} =~ m/(\d+\s*\w+)/;
  my $ram = $1;
  return parseBytes($ram);
}

############################################################################
# Is the given host a virtual machine?
#
# @param host  Host name or RemoteMachine
#
# @return true iff the machine is some flavor of VM
##
sub isVirtualMachine {
  my ($host) = assertNumArgs(1, @_);

  # Sometimes we get passed a RemoteMachine or UserMachine.
  # We really just want a hostname.
  if (blessed($host)) {
    $host = $host->getName();
  }

  my $result = runCommand($host, "systemd-detect-virt");
  chomp($result->{stdout});
  if (($result->{status} == 1) && ($result->{stdout} eq "none")) {
    return 0;
  }
  if (($result->{status} == 0) && ($result->{stdout} ne "")) {
    return 1;
  }

  # It used to be that all of our "farm" machines were virtual machines, and
  # the others were real machines. This is no longer necessarily the case.
  # However "farm" machines from Fedora 28 and RHEL 7.5 (the initial
  # distributions for which VDO was published) have systemd-detect-virt
  # available.  So if systemd-detect-virt wasn't found, the system is probably
  # a crufty old machine and we apply a name heuristic to determine if it is
  # virtual.
  #
  # We exclude machines which have a FQDN which does not match at least one
  # of a specified set of suffix regexes.
  if (($host =~ /\./)
      && (!(grep { $host =~ qr($_)} @{_virtualMachineFQDNSuffixes()}))) {
    # If we couldn't run systemd-detect-virt or it gave an error, report that.
    if (defined($result->{error})) {
      croak("unable to get virtualization status for $host: $result->{error}");
    }
    # Some unexpected failure mode? Log details so we can make a more
    # informative error message later.
    $log->error("unknown virtualization detection failure for $host: "
                . "status=$result->{status} stdout=[ $result->{stdout} ] "
                . "stderr=[ $result->{stderr} ]");
    croak("unable to get virtualization status");
  }

  my $regex = _getImplementation()->{virtualMachine}->{name}->{regex};
  return $host =~ qr($regex);
}

############################################################################
# Make a lab machine of the proper type based upon the name of the host
#
# @param hostname  The hostname
#
# @return the lab machine
##
sub _makeLabMachine {
  my ($hostname) = assertNumArgs(1, @_);
  foreach my $class (@{_supportedMachineClasses()}) {
    if (($hostname =~ $class->getHostRE()) && $class->hostCheck($hostname)) {
      return $class->new(hostname => $hostname);
    }
  }
  confess("'$hostname' is an unrecognized hostname");
}

############################################################################
# Reboot a list of machines and wait for them to come back
#
# @param hostnames  Hostnames of the machines
#
# @croaks if any of the machines fail to reboot and respond to ssh
##
sub rebootMachines {
  my @hostnames = assertMinArgs(1, @_);
  $log->info("Rebooting " . join(",", @hostnames));
  _restartMachinesAndWait("reboot", \@hostnames);
  $log->info("Reboot complete " . join(",", @hostnames));
}

############################################################################
# On systems where it is necessary, adjust the boot device that'll be
# used by the system firmware so that we'll boot into the current OS
# again.
##
sub fixNextBootDevice {
  my ($host) = assertNumArgs(1, @_);
  _makeLabMachine($host)->fixNextBootDevice();
}

############################################################################
# Set the hung task timeout.
#
# @param  host  The name of the host
# @oparam t     The hung task timeout.  If not specified, a reasonable default
#               for this type of host will be used.
##
sub setHungTaskTimeout {
  my ($host, $t) = assertMinMaxArgs([undef], 1, 2, @_);
  _makeLabMachine($host)->setHungTaskTimeout($t);
}

############################################################################
# Wait for a list of machines to respond to ping and ssh
#
# @param pingWait     How long to wait before checking for ping
# @param pingTimeout  Maximum time to wait for ping
# @param sshWait      How long to wait after ping and before ssh checks
# @param sshTimeout   Maximum time to wait for ssh
# @param hostnames    List of hostnames
#
# @croaks if any of the machines fail to respond to ping or ssh within the
#         specified timeouts.
##
sub waitForMachines {
  my ($pingWait, $pingTimeout, $sshWait, $sshTimeout, @hostnames)
    = assertMinArgs(4, @_);
  $log->debug("Waiting $pingWait seconds before pinging machines.");
  sleep($pingWait);
  $log->debug("Using ping to see which machines have come back alive.");
  # Wait for machines to come back alive.
  foreach my $hostname (@hostnames) {
    _waitForMachinePing(5, $pingTimeout, $hostname);
  }
  $log->debug("Sleeping for $sshWait seconds to let ssh start up");
  sleep($sshWait);
  foreach my $hostname (@hostnames) {
    _waitForMachineSSH(5, $sshTimeout, $hostname);
  }
}

############################################################################
# Restart a list of machines and wait for them to come back. This can
# include powering on a machine that's been switched off, if we know
# how.
#
# @param  restart    Restart procedure name (reboot, emergencyRestart, powerOn)
# @param  hostnames  Hostnames of the machines
#
# @croaks if any of the machines fail to reboot, respond to ssh and sssd is
#         not active.
##
sub _restartMachinesAndWait {
  my ($restart, $hostnames) = assertNumArgs(2, @_);
  my %labMachines = map { ($_, _makeLabMachine($_)) } @$hostnames;
  my @labMachines = values(%labMachines);
  while (@labMachines) {
    my %preRestartBootIds = map { $_->{hostname} => $_->bootId() } @labMachines;
    my $restartTime = time();
    map { $_->$restart() } @labMachines;

    my $timeout = max(map { $_->{restartTimeout} } @labMachines);
    while (1) {
      my @troubles;
      my $period = time() - $restartTime;
      for my $labMachine (@labMachines) {
        my $bootId = $labMachine->bootId();
        if ($bootId eq "") {
          push(@troubles, "$labMachine->{hostname} is not responding");
        } elsif ($restart eq 'powerOn') {
          # We assume either the node was already confirmed to have been off,
          # or the caller is just trying to ensure that the node is on, and
          # either way it's sufficient for us to be able to retrieve the
          # boot id.
        } elsif ($bootId eq $preRestartBootIds{$labMachine->{hostname}}) {
          push(@troubles, "$labMachine->{hostname} has not shutdown");
        }
      }
      if (scalar(@troubles) == 0) {
        # Network back online, sshd may not be up yet.
        last;
      }
      assertLENumeric($period, $timeout,
                      "${timeout}-second timeout expired waiting for restart: "
                      . join(" and ", @troubles));
      sleep(2);
    }

    for my $labMachine (@labMachines) {
      my $timeRemaining = max($restartTime + $timeout - time(), 5);
      my $hostname      = $labMachine->{hostname};
      _waitForMachineSSH(2, $timeRemaining, $hostname);
      # Recalculate remaining time and wait for SSSD to be active.
      $timeRemaining = max($restartTime + $timeout - time(), 5);
      _waitForMachineSSSD(2, $timeRemaining, $hostname);
      if ($labMachine->checkReboot()) {
        delete $labMachines{$hostname};
        $labMachine->setHungTaskTimeout();
        $labMachine->fixNextBootDevice();
      } else {
        $log->warn("post-reboot checks failed for $hostname, rebooting again");
      }
    }

    @labMachines = values(%labMachines);
  }
}

############################################################################
# Wait for the given hostname to respond to pings
#
# @param waitTime   How long to wait between checks
# @param maxTime    The maximum time to wait
# @param hostname   The hostname of the machine you are waiting on
#
# @croaks if the maximum ping time is exceeded
##
sub _waitForMachinePing {
  my ($waitTime, $maxTime, $hostname) = assertNumArgs(3, @_);
  my $startTime = time();
  while (1) {
    my $pingResult = `ping -c 1 $hostname`;
    if ($pingResult !~ /0 received/) {
      return;
    }
    my $period = time() - $startTime;
    my $periodText = timeToText($period);
    assertTrue($period < $maxTime,
               "waitForMachinePing($hostname) failed after $periodText");
    sleep($waitTime);
  }
}

############################################################################
# Wait for the given hostname to respond to SSH.
#
# @param waitTime   How long to wait between checks
# @param maxTime    The maximum time to wait
# @param hostname   The hostname of the machine you are waiting on
#
# @croaks if more than $maxTime seconds elapses without being able to ssh
#         to the machine.
##
sub _waitForMachineSSH {
  my ($waitTime, $maxTime, $hostname) = assertNumArgs(3, @_);
  my $startTime = time();
  my $error;
  while (1) {
    if (runCommand($hostname, "true")->{returnValue} == 0) {
      return;
    }
    my $period = time() - $startTime;
    my $periodText = timeToText($period);
    assertTrue($period < $maxTime,
               "waitForMachineSSH($hostname) failed after $periodText");
    sleep($waitTime);
  }
}

############################################################################
# Wait for the given hostname to respond to pings
#
# @param waitTime   How long to wait between checks
# @param maxTime    The maximum time to wait
# @param hostname   The hostname of the machine you are waiting on
#
# @croaks if the maximum ping time is exceeded
##
sub _waitForMachineSSSD {
  my ($waitTime, $maxTime, $hostname) = assertNumArgs(3, @_);
  my $startTime = time();
  while (1) {
    my $athinfoResult = athinfo($hostname, "sssd");
    if ($athinfoResult =~ /active/) {
      return;
    }
    my $period = time() - $startTime;
    my $periodText = timeToText($period);
    assertTrue($period < $maxTime,
               "waitForMachineSSSD($hostname) failed after $periodText");
    sleep($waitTime);
  }
}

############################################################################
# Identify the subclass used when dealing with a particular machine.
#
# This is internal information for use in testing the classification of
# machines.
#
# @param hostname  The hostname
#
# @return the last component of the name of the Perl class used
#         for the lab machine object
##
sub _machineClass {
  my ($hostname) = assertNumArgs(1, @_);
  my $className = ref(_makeLabMachine($hostname));
  my @nameComponents = split("::", $className);
  return $nameComponents[-1];
}

1;
