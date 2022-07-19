##
# Common constants defined for Permabit modules in //eng/main and shared by
# many projects and branches. Constants defined here are expected to be used
# and re-exported (and values possibly overridden) by the version of
# Constants.pm in each project or branch.
#
# $Id$
##
package Permabit::MainConstants;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use base qw(Exporter);

our $VERSION = "1.1";
our @EXPORT = qw(
  $BACKUP_INTERFACE_NUMBER
  $CODENAME
  $CURRENT_VERSION_FILE
  $DAY
  $DEFAULT_DATABASE_SERVER
  $DEFAULT_STORE_SIZE
  $DEFAULT_U1_SIZE
  $EB
  $FARM_U1_LIMIT
  $FOREVER
  $GB
  $HARVARD_U1_SIZE
  $HOUR
  $KB
  $MAX_TIME_SKEW
  $MB
  $MICROSECOND
  $MILLISECOND
  $MINUTE
  $NANOSECOND
  $NIGHTLY_DATE_STR_FMT
  $PB
  $REAL_INTERFACE
  $ROOT_LIMIT
  $SCP_OPTIONS
  $SECTOR_SIZE
  $SSH_OPTIONS
  $STAFF_GID
  $TB
  $U1_LIMIT
  $VAR_LIMIT
  $VFARM_U1_LIMIT
  $VIRTUAL_INTERFACE
  $YEAR
  %COMMAND_PATH
  @CODENAMES
  @RELEASE_MAPPINGS
  humanUsersEmail
  nonhumanUsers
);

our $FOREVER = -1;
our $KB      = 1024;
our $MB      = 1024 * 1024;
our $GB      = 1024 * 1024 * 1024;
our $TB      = 1024 * 1024 * 1024 * 1024;
our $PB      = 1024 * 1024 * 1024 * 1024 * 1024;
our $EB      = 1024 * 1024 * 1024 * 1024 * 1024 * 1024;

# The size of a disk sector. Even though disks are moving
# towards 4k blocks, they are still accessible via 512 byte
# sectors and doubt that it will change soon.
our $SECTOR_SIZE = 512;

our $NANOSECOND  = 1.0e-9;
our $MICROSECOND = 1.0e-6;
our $MILLISECOND = 1.0e-3;
our $MINUTE      = 60;
our $HOUR        = 60  * $MINUTE;
our $DAY         = 24  * $HOUR;
our $YEAR        = 365 * $DAY;

# Remote access options used for ssh and scp.  The -o options are common to
# both commands.
#
# The client sends a ping message every ServerAliveInterval seconds, and
# expects the server to respond to it.  If there are no responses to
# ServerAliveCountMax pings, then the client times out the connection.  We
# specify a 10 minute timeout, spelled as ten 30 second intervals, so that we
# will detect any 330 second network outage.
my $SSH_CONFIG_OPTIONS = ("-oBatchMode=yes"
                          . " -oConnectTimeout=120"
                          . " -oServerAliveCountMax=10"
                          . " -oServerAliveInterval=30"
                          . " -oTCPKeepAlive=yes");
# As of 2019-06-05, some of the Red Hat S/390 systems have duplicate MAC
# addresses and attempt to use the same IPv6 addresses. To avoid connecting to
# the wrong host, we must avoid using IPv6, until this problem is fixed.
our $SCP_OPTIONS = "-pqr4 $SSH_CONFIG_OPTIONS";
our $SSH_OPTIONS = "-A -4 -x $SSH_CONFIG_OPTIONS";

# checkServer constants
our $BACKUP_INTERFACE_NUMBER     = 21;
our $FARM_U1_LIMIT               = 50 * $GB;
our $MAX_TIME_SKEW               = 0.5;
our $DEFAULT_STORE_SIZE          = 5120 * $MB;
our $DEFAULT_U1_SIZE             = 47185920; # the size of the partition
our $HARVARD_U1_SIZE             = 39485440; # the size of the partition
our $ROOT_LIMIT                  = 256 * $MB;
our $STAFF_GID                   = 50;
our $U1_LIMIT                    = 34 * $GB;
our $VAR_LIMIT                   = 100 * $MB;
our $VFARM_U1_LIMIT              = 40 * $GB;

# Release info
# These must be listed in order of newest release to oldest.
our @RELEASE_MAPPINGS = (
  q(cecil    4.0  lenny          albireo-cecil),
  q(chalmers 4.1  lenny          albireo-chalmers),
  q(duffman  5.0  squeeze,lenny  albireo),
  # Albireo probably doesn't belong here because it's not an OS,
  # it's a configuration.
  q(albireo   x   lenny,precise,rhel6,sles11sp2,squeeze,wheezy  albireo),
);
our @CODENAMES = map { (split(/\s+/, $_))[0] } @RELEASE_MAPPINGS;
our $CODENAME = $CODENAMES[0];

# Interface types
our $VIRTUAL_INTERFACE = 0;
our $REAL_INTERFACE = 1;

# Prevent path searches for some commands
our %COMMAND_PATH = (
                     "apt-get" => "/usr/bin/apt-get",
                     arp       => "/usr/sbin/arp",
                     bash      => "/bin/bash",
                     chmod     => "/bin/chmod",
                     cmp       => "/usr/bin/cmp",
                     cp        => "/bin/cp",
                     df        => "/bin/df",
                     diff      => "/usr/bin/diff",
                     date      => "/bin/date",
                     grep      => "/bin/grep",
                     ifconfig  => "/sbin/ifconfig",
                     ifdown    => "/sbin/ifdown",
                     ifup      => "/sbin/ifup",
                     ln        => "/bin/ln",
                     logger    => "/usr/bin/logger",
                     ls        => "/bin/ls",
                     mkdir     => "/bin/mkdir",
                     netstat   => "/bin/netstat",
                     pidof     => "/bin/pidof",
                     rm        => "/bin/rm",
                     route     => "/sbin/route",
                     rsync     => "/usr/bin/rsync",
                     scam      => "/sbin/scam",
                     ssh       => "/usr/bin/ssh",
                     sudo      => "/usr/bin/sudo",
                     sync      => "/bin/sync",
                     tail      => "/usr/bin/tail",
                     test      => "/usr/bin/test",
                     vmstat    => "/usr/bin/vmstat",
                    );

# YYYY-MM-DD-HH-MM string fmt (used by nightly and some other things)
our $NIGHTLY_DATE_STR_FMT = "%Y-%m-%d-%H-%M";

# The default location of the current version file relative to the top of a
# a project branch.
our $CURRENT_VERSION_FILE = 'src/tools/installers/CURRENT_VERSION';

# Environment-specific implementation.
our $IMPLEMENTATION;

############################################################################
# Return the instance which provides the Configured controlled functionality.
#
# @return the Configured functional instance
##
sub _getImplementation {
  if (!defined($IMPLEMENTATION)) {
    eval("use Permabit::MainConstants::Implementation");
    $IMPLEMENTATION = Permabit::MainConstants::Implementation->new();
  }

  return $IMPLEMENTATION;
}

############################################################################
# Return the map of human users to email addresses.
#
# @return human users email mapping, may be empty
##
sub humanUsersEmail {
  return _getImplementation()->{users}->{human};
}

############################################################################
# Return the list of non-human users.
#
# @return non-human users list, may be empty
##
sub nonhumanUsers {
  return _getImplementation()->{users}->{nonHuman};
}

1;
