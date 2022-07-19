##
# Check system disk space:
# root needs $ROOT_LIMIT bytes
# /var needs $VAR_LIMIT bytes
# /var/log needs $VAR_LIMIT bytes
# These may not be separate filesystems
#
# $Id$
##
package CheckServer::Test::SystemSpace;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);
use Permabit::Constants;

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my @FILE_SYSTEMS = ('/', '/var', '/var/log');

my %FILE_SYSTEM_LIMITS = (
  '/'        => $ROOT_LIMIT - 110182409,
  '/var'     => $VAR_LIMIT,
  '/var/log' => $VAR_LIMIT,
);

my $DEVICE_RE = '^/dev/(\S+)\s+\d+\s+\d+\s+(\d+)\s+\d+%\s+/.*$';

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my %devices = ();
  foreach my $fileSystem (@FILE_SYSTEMS) {
    my $df = $self->runCommand("df -P -k $fileSystem");
    if ($df =~ /$DEVICE_RE/m) {
      my $device    = $1;
      my $available = $2 * 1024; # convert to bytes
      my $limit = $FILE_SYSTEM_LIMITS{$fileSystem};
      if ($available >= $limit) {
        next;
      }

      if ($fileSystem eq '/var/log') {
        if ($self->hasCommand('journalctl')) {
          $self->addFixes("journalctl --vacuum-size=$available");
        }

        if ($self->hasCommand('logrotate')) {
          $self->addFixes("logrotate --force /etc/logrotate.conf");
        }
      }

      if ($devices{$device} && ($limit < $devices{$device}->{limit})) {
        $devices{$device}->{limit} = $limit;
        next;
      }

      $devices{$device} = { fileSystem => $fileSystem,
                            available  => $available,
                            limit      => $limit
                          };
      last;
    }
  }

  foreach my $device (sort(keys(%devices))) {
    my $deviceInfo = $devices{$device};
    $self->fail("$deviceInfo->{fileSystem} is too full, "
                . "($deviceInfo-{available} < $deviceInfo->{limit})");
  }
}

1;

