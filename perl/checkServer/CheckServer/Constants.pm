##
# This file contains some of the constants that are used by the main
# checkServer.pl script.
#
# $Id$
##
package CheckServer::Constants;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use base qw(Exporter);

use Permabit::Constants;
use Permabit::Utils qw(getScamVar);

our @EXPORT = qw(
  @DIST_CLASSES

  %DAEMONS
  $MAX_KERN_LOG_SIZE
  $MIN_MEMORY
  $NIGHTLY_UID
  @SERVICES_NOT_STARTED_AT_BOOT
  $STAFF_GID
  $SSH_KNOWN_HOSTS

  @BAD_DIRS
  @CHECKED_DIRS
  @NO_SYMLINK_DIRS
  @TEST_DIRS
  @SYSTEM_BIN_DIRS
  $BUILD_DIRS

  $LVM_CONF

  @BAD_FILES
  @OK_SYMLINK_FILES

  @BAD_PROGRAMS
  @BAD_PROCESSES

  %testModules

  @IGNORE_CRASH_PATTERNS
);

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
                       RAWHIDE
                       JESSIE
                       LENNY
                       SQUEEZE
                       PRECISE
                       SLES11SP2
                       SLES11SP3
                       RHEL6
                       RHEL7
                       RHEL8
                       RHEL8DEBUG
                       RHEL9
                       RHEL9DEBUG
                       RHEL10
                       RHEL10DEBUG
                       WHEEZY39
                       WHEEZY310
                       VIVID
                       XENIAL);

# The following are basic constants used
our $MAX_KERN_LOG_SIZE    = 55 * $MB;
our $MIN_MEMORY           = 950 * 1024;
our $NIGHTLY_UID          = 1030;
our @SERVICES_NOT_STARTED_AT_BOOT = ('heartbeat', 'samba');

# Daemon processes that must be running.
#  name of process => name of /etc/init.d script to start it (if any)
our %DAEMONS
  = (
     cron     => "cron",
     ntpd     => "ntp",
     rsyslogd => "rsyslog",
     smartd   => "smartmontools",
    );

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
our @NO_SYMLINK_DIRS = (
  '/config/etc/ha.d',
  '/etc/default',
  '/etc/ha.d',
  '/etc/samba',
  '/config/etc/samba',
);
our @SYSTEM_BIN_DIRS = (
  '/usr/local/sbin',
  '/usr/local/bin',
  '/usr/sbin',
  '/usr/bin',
  '/sbin',
  '/bin',
  '/usr/X11R6/bin',
);
our @TEST_DIRS    = ("/u1/CliqueTest-*", "/u1/PerfTest-*");

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
  '/lib64/dmeventd-vdo.so',
  '/tmp/.X3-lock',
  '/tmp/vdo.lock',
  '/u1/fake-block-device',
  '/u1/*-tmp_loopback_file',
  '/usr/share/locale/en/LC_MESSAGES/vdo.mo',
);
our @OK_SYMLINK_FILES = ('/etc/ha.d/resource.d/IPv6addr');

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
  fio
  processCorruptorTrace
  processTrace
  vdo
  vdoFormat
  vdoformat
  vdoMonitor
  vdoPrepareUpgrade
  vdoStats
);

# Processes that shouldn't be running on the machine even if the
# executables belong there.
our @BAD_PROCESSES = qw(
  valgrind
);

our %testModules = (
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

1;
