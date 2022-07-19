##
# Check that kernel logs are not too large and look for problems in them.
#   under --fix:
#     - If possible, use logrotate to rotate large kern.log and then
#       rename it to kern.large.log.
#     - Rename large kern.log.* to kern.large.log* so that future
#       runs of checkServer will not try to grep them.
#
# $Id$
##
package CheckServer::Test::KernLog;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use CheckServer::Constants;

use base qw(CheckServer::AsyncTest);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

# Messages from early in the reboot sequence
my $BOOT_STRINGS
  = join('|',
         "/proc/kmsg started",                 # do not know
         "000000] Linux version ",             # old RHEL7 or Fedora
         " Initializing cgroup subsys cpuset", # Red Hat
        );

# Messages that indicate a problem in the running kernel.  Be careful not to
# include a single word in this list (like "OOPS").  An arbitrary sequence of
# letters can be embedded in a UUID.  Note that all of these strings include
# at least one space.
my $BUG_STRINGS
  = join('|',
         " BUG",
         "Busy inodes after unmount",
         "general protection fault",
         '[kv]malloc memory used \(\S+ bytes in \S+ blocks\) is returned',
        );


########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  if ($self->hasCommand('logrotate')) {
    $self->checkLatestLog();
  } else {
    $self->checkAllLogs();
  }

  if ($self->hasCommand('journalctl')) {
    $self->checkJournalctlErrors();
  } else {
    $self->checkKernLogErrors();
  }
}

########################################################################
# Check the size of the latest kern.log, fix with logrotate.
##
sub checkLatestLog {
  my ($self)      = assertNumArgs(1, @_);
  my $kernLog     = '/var/log/kern.log';
  my $kernLogSize = (-s $kernLog) || 0;
  if ($kernLogSize > $MAX_KERN_LOG_SIZE) {
    $self->fail("$kernLog is too large ($kernLogSize bytes)");
    $self->addFixes(join(' && ',
                         'logrotate /etc/logrotate.d/kern',
                         'mv /var/log/kern.log.1 /var/log/kern.large.log'));
  }
}

########################################################################
# Check all the kernel logs, rotate by hand to fix.
##
sub checkAllLogs {
  my ($self) = assertNumArgs(1, @_);
  # XXX: Not all lfarms have logrotate so use the older implementation.
  # This should go away eventually.
  # YYY: Perhaps now?
  foreach my $logFile ($self->runCommand('ls -t1 /var/log/kern.log*')) {
    my $logSize = -s $logFile;
    if ($logSize > $MAX_KERN_LOG_SIZE) {
      my $largeLog = $logFile;
      $largeLog =~ s|/kern.|/kern.large.|;
      $self->fail("$logFile is too large ($logSize bytes)");
      $self->addFixes("mv $logFile $largeLog");
    }
  }
}

########################################################################
# Scan for errors since the last boot using journalctl.
##
sub checkJournalctlErrors {
  my ($self) = assertNumArgs(1, @_);
  if (!open(LOG, "journalctl -k -o short-monotonic |")) {
    $self->fail("Failed to run journalctl", 1);
  } else {
    map({ $self->fail($_) } grep({ $_ =~ /$BUG_STRINGS/ } <LOG>));
    close(LOG);
  }
}

########################################################################
# Scan for errors in kern.log.*.
##
sub checkKernLogErrors {
  my ($self) = assertNumArgs(1, @_);
  my @errors = ();
  my $foundLatestStart = 0;
  foreach my $logFile ($self->runCommand('ls -t1 /var/log/kern.log*')) {
    if ($foundLatestStart) {
      next;
    }

    my @currentFileErrors = ();
    if (!open(LOG, "zegrep -a '$BOOT_STRINGS|$BUG_STRINGS' $logFile |")) {
      push(@errors, "Failed to read $logFile\n");
      next;
    }

    while (my $line = <LOG>) {
      # Reset each time a reboot is noted.
      if ($line =~ /$BOOT_STRINGS/) {
        $foundLatestStart  = 1;
        @currentFileErrors = ();
        next;
      }

      if ($line =~ /$BUG_STRINGS/) {
        push(@currentFileErrors, $line);
      }
    }

    close(LOG);
    unshift(@errors, @currentFileErrors);
  }

  if (@errors) {
    $self->fail(join("This machine is unstable: Kernel bug noted:\n",
                     @errors), 1);
  }
}

1;
