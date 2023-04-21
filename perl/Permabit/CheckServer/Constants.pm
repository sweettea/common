##
# This file contains some of the constants that are used by the main
# checkServer.pl script.
#
# $Id$
##
package Permabit::CheckServer::Constants;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use base qw(Exporter);

use Permabit::CheckServer::Constants::Implementation;
use Permabit::Constants;
use Permabit::Utils qw(getScamVar);

our @EXPORT = qw(
  @ARCH_CLASSES
  @DIST_CLASSES

  %DAEMONS
  $EXPERIMENTAL_HWRAID_SIZE
  $MAX_KERN_LOG_SIZE
  $MEGARAID_DEVICE_SIZE
  $MEGARAID_PARTITION

  $IPCRM
  $IPCS
  $MACH_DIR
  $OPS_DIR
  $OPS_SCRIPTS
  $FIXSSH
  $SSH_ARCHIVE
  $SSH_KNOWN_HOSTS

  @BAD_DIRS
  @CHECKED_DIRS
  @NO_SYMLINK_DIRS
  @TEST_DIRS
  @SYSTEM_BIN_DIRS
  $BUILD_DIRS

  $LVM_CONF

  @BAD_FILES

  @BAD_PROGRAMS
  @BAD_PROCESSES

  %testModules

  @IGNORE_CRASH_PATTERNS

  farmNFSServer
  redhatNFSServer
  triageUserName
  triageUserUid
);


# This is the list of officially supported architectures for RHEL
our @ARCH_CLASSES = qw(AARCH64
                       PPC64LE
                       S390X
                       X86_64);

# The following are the distribution classes that are supported
our @DIST_CLASSES = qw(CENTOS8
                       FEDORA27
                       FEDORA28
                       FEDORA29
                       FEDORA30
                       FEDORA31
                       FEDORA32
                       FEDORA33
                       FEDORA34
                       FEDORA35
                       FEDORA36
                       FEDORA37
                       FEDORA38
                       RAWHIDE
                       RHEL6
                       RHEL7
                       RHEL8
                       RHEL8DEBUG
                       RHEL9
                       RHEL9DEBUG);

# The following are basic constants used
our $BIGMEM = 16777216;  # Minimal amount to belong in BIGMEM class
our $EXPERIMENTAL_HWRAID_SIZE = 764838674432; # RAID size with 6 120G SSD
our $MAX_KERN_LOG_SIZE    = 55 * $MB;
our $MEGARAID_DEVICE_SIZE = 892311961600;
our $MEGARAID_PARTITION   = getScamVar('MEGARAID') . '-part1';

# Daemon processes that must be running.
#  name of process => name of /etc/init.d script to start it (if any)
our %DAEMONS
  = (
     cron     => "cron",
     ntpd     => "ntp",
     rsyslogd => "rsyslog",
     smartd   => "smartmontools",
    );

# The following are various paths that are used
our $IPCRM           = "/usr/bin/ipcrm";
our $IPCS            = "/usr/bin/ipcs";
our $MACH_DIR        = '/permabit/mach';
our $OPS_DIR         = '/permabit/ops';
our $OPS_SCRIPTS     = "$OPS_DIR/scripts";
our $FIXSSH          = "$OPS_SCRIPTS/fixssh";
our $SSH_ARCHIVE     = "$OPS_SCRIPTS/ssh_archive";
our $SSH_KNOWN_HOSTS = "$MACH_DIR/files/ssh_known_hosts";

# The following are various directory constants
our @BAD_DIRS = (
  '/dev/vdo0',
  '/dev/vdo1',
  '/mnt/VDOdir',
  '/mnt/raid0/mockfs',
  '/mnt/raid0/scratch',
  '/u1/mockfs',
  '/u1/perf_grapher',
  '/u1/recorderfsMnt',
  '/var/lock/vdo',
);
our @CHECKED_DIRS    = ("/u1");
our @SYSTEM_BIN_DIRS = (
  '/usr/local/sbin',
  '/usr/local/bin',
  '/usr/sbin',
  '/usr/bin',
  '/sbin',
  '/bin',
);
our @TEST_DIRS    = ("/u1/CliqueTest-*", "/u1/PerfTest-*");
# These dirs must be owned by nightly, but we don't need to check sub dirs
our $BUILD_DIRS   = "/u1/*-builds/";

# The following are various configuration files
our $LVM_CONF      = "/etc/lvm/lvm.conf";

# The following are various files that we are looking for
our @BAD_FILES = (
  '/etc/bash_completion.d/vdostats',
  '/etc/mtab.tmp',
  '/etc/mtab~',
  '/etc/profile.d/pbit-test-env.csh',
  '/etc/profile.d/pbit-test-env.sh',
  '/etc/vdoconf.xml',
  '/etc/vdoconf.yml',
  '/etc/vdocustom.xml',
  '/etc/violetconf.xml',
  '/lib64/dmeventd-vdo.so',
  '/tmp/.X3-lock',
  '/tmp/vdo.lock',
  '/u1/fake-block-device',
  '/u1/*-tmp_loopback_file',
  '/usr/share/locale/en/LC_MESSAGES/vdo.mo',
);

# The following are related to VDO, Albireo, and testing of them
our @BAD_PROGRAMS = qw(
  albconfig
  albcreate
  albfill
  albping
  albreader
  albscan
  albserver
  albtest
  albvalidate
  azurevalidate
  azureping
  azurecreate
  azureserver
  azurefill
  fio
  processCorruptorTrace
  processTrace
  vdo
  vdoFormat
  vdoformat
  vdoMonitor
  vdoPrepareUpgrade
  vdoStats
  violetformat
  violetFormat
);

# Processes that shouldn't be running on the machine even if the
# executables belong there.
our @BAD_PROCESSES = qw(
  valgrind
);

our %testModules = (
                    "albireo"         => [],
                    "kvdo"            => ["dedupe"],
                    "pbitcorruptor"   => ["corruptor"],
                    "pbitdory"        => ["dory"],
                    "pbitendiosubmit" => ["endiosubmit"],
                    "pbitflushnop"    => ["flushnop"],
                    "pbitfua"         => ["fua"],
                    "pbittracer"      => ["tracer"],
                    "testfua"         => ["dory", "fua"],
                    "uds"             => [],
                    "zubenelgenubi"   => [],
                   );

# List of regexps maching /var/crash/*crash files that should be ignored.
our @IGNORE_CRASH_PATTERNS = (
  # systemd aborts its own journal process when the system hangs for 180+ secs.
  qr/systemd_systemd-journald/,
);

# Environment-specific implementation.
our $IMPLEMENTATION;

############################################################################
# Return the instance which provides the Configured controlled functionality.
#
# @return the Configured functional instance
##
sub _getImplementation {
  if (!defined($IMPLEMENTATION)) {
    $IMPLEMENTATION = Permabit::CheckServer::Constants::Implementation->new();
  }

  return $IMPLEMENTATION;
}

############################################################################
# Return the name of the farm lab nfs server.
#
# @return the farm lab nfs server name, may be undefined
##
sub farmNFSServer {
  return _getImplementation()->{nfs}->{farm};
}

############################################################################
# Return the name of the Red Hat nfs server.
#
# @return the Red Hat server name, may be undefined
##
sub redhatNFSServer {
  return _getImplementation()->{nfs}->{redhat};
}

############################################################################
# Return the name of the triage user.
#
# @return the triage user name, may be undefined
##
sub triageUserName {
  return _getImplementation()->{triage}->{user};
}

############################################################################
# Return the uid of the triage user.
#
# @return the triage user uid, may be undefined
##
sub triageUserUid {
  return _getImplementation()->{triage}->{uid};
}

1;
