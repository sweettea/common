##
# Perl object that represents a lab machine.
#
# This class can be subclassed to make machine behaviors particular to a
# class of machines available to the perl code.  For example, some host are
# virtual machines that can be controlled via the real machine presenting
# the virtual machine.
#
# $Id$
##
package Permabit::LabUtils::LabMachine;

use strict;
use warnings FATAL => qw(all);
use Carp;
use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(
  assertDefined
  assertMinArgs
  assertMinMaxArgs
  assertNumArgs
);
use Permabit::Constants;
use Permabit::PlatformUtils qw(isFedora);
use Permabit::SystemUtils qw(
  assertCommand
  athinfo
  getScamVar
  runCommand
);
use Permabit::Utils qw(getUserName);
use Storable qw(dclone);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

#############################################################################
# @paramList{new}
my %properties
  = (
     # @ple The name of the host machine
     hostname        => undef,
     # @ple How long to allow before the kernel complains about a hung task
     hungTaskTimeout => 2 * $MINUTE,
     # @ple How long to wait for a restarted machine to respond to ssh
     restartTimeout  => 18 * $MINUTE,
    );
##

#############################################################################
# Creates a C<Permabit::LabUtils::LabMachine>. C<new> optionally takes
# arguments, in the form of key-value pairs.
#
# @params{new}
#
# @return a new C<Permabit::LabUtils::LabMachine>
##
sub new {
  my $invocant = shift;
  my $class = ref($invocant) || $invocant;
  my $self = bless { %{ dclone(\%properties) },
                     # Overrides previous values
                     @_,
                   }, $class;
  assertDefined($self->{hostname});
  return $self;
}

############################################################################
# Do an emergency restart on the machine.  Does not do a clean shutdown.
##
sub emergencyRestart {
  my ($self) = assertNumArgs(1, @_);
  eval {
    # This is in an eval because this call will generate an EPIPE error
    $self->setProcFile("b", "/proc/sysrq-trigger");
  };
}

############################################################################
# Get the regular expression for recognizing this class of lab machine
#
# @return the regular expression
##
sub getHostRE {
  my ($package) = assertNumArgs(1, @_);
  return qr/^\w+/;
}

############################################################################
# Perform an optional secondary test whether a specific host belongs
# to the class.
#
# @param hostname  The name of the host
#
# @return true iff the host belongs to the current class (or its
#         subclasses)
##
sub hostCheck {
  my ($package, $hostname) = assertNumArgs(2, @_);
  return 1;
}

############################################################################
# On systems where it is necessary, adjust the boot device that'll be
# used by the system firmware so that we'll boot into the current OS
# again.
##
sub fixNextBootDevice {
  my ($self) = assertNumArgs(1, @_);
  # Most machines have nothing to do.
  return;
}

############################################################################
# Reboot the machine
##
sub reboot {
  my ($self) = assertNumArgs(1, @_);
  # In the limited-memory or kmemleak cases we need the grub configuration to
  # be reloaded, even if a machine uses kexec.  Hence the coldreboot.
  #
  # Also, there's no guarantee that the command will 'succeed', so don't check
  # its return value.  Finally, we need to kill all processes (i.e. the
  # BashSession's bash).
  my $user = getUserName();
  runCommand($self->{hostname},
             "(sudo coldreboot || sudo reboot)"
             . " && trap '' TERM"
             . " && sudo pkill -u $user");
}

############################################################################
# Turn the machine's power on.
##
sub powerOn {
  confess("Don't know how to power on a generic lab machine.");
}

############################################################################
# Turn the machine's power off.
##
sub powerOff {
  my ($self) = assertNumArgs(1, @_);
  assertCommand($self->{hostname}, "sudo shutdown -P now");
}

############################################################################
# Do an emergency power-off of a machine. Do *not* shut down cleanly.
##
sub emergencyPowerOff {
  confess("Don't know how to emergency-power-off a generic lab machine.");
}

############################################################################
# Return the current status of power for the machine.
#
# @return   1 if power is on, 0 if power is off
#
# @croaks   if the power state cannot be determined
##
sub getPowerStatus {
  my ($self) = assertNumArgs(1, @_);
  croak("Don't know how to check power status on a generic lab machine");
}

############################################################################
# Set the hung task timeout.
#
# @oparam t  The hung task timeout.  If not specified, a reasonable default
#            for this type of host will be used.
##
sub setHungTaskTimeout {
  my ($self, $t) = assertMinMaxArgs([undef], 1, 2, @_);
  $t //= $self->{hungTaskTimeout};
  if (!isFedora($self->{hostname})) {
    # As per VDO-4200, we don't care about this testing on Fedoras where it
    # is not available by default, so don't try to set it.
    $self->setProcFile($t, "/proc/sys/kernel/hung_task_timeout_secs");
  } else {
    $log->debug("Not setting hung_task_timeout_secs because Fedora doesn't"
                . " have it.");
  }
}

############################################################################
# Write a file in the /proc filesystem
#
# @param contents  Text to be written
# @param path      Path name
##
sub setProcFile {
  my ($self, $contents, $path) = assertNumArgs(3, @_);
  # What we want to do is "echo $contents >$path", but the destination file
  # cannot be written without superuser permissions.
  assertCommand($self->{hostname}, "echo $contents | sudo dd of=$path");
}

############################################################################
# Get the boot id of the machine.
#
# The boot id changes with every boot; by recording the current boot id and
# querying the machine for a change in the boot id (using string comparison)
# this is a reliable way to determine if a system has rebooted.
#
# @return the boot id of the most recent machine boot or the empty string if
#         the machine is not responding
##
sub bootId {
  my ($self) = assertNumArgs(1, @_);
  return athinfo($self->{hostname}, "boot_id");
}

############################################################################
# Get the time that the machine has been up
#
# @return the number of seconds since the machine has been booted,
#         or the empty string if the machine is not responding
##
sub uptime {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{hostname} eq "localhost") {
    # For localhost, read it from /proc/uptime directly
    my $result = runCommand("localhost", "cat /proc/uptime | cut -d' ' -f 1");
    return $result->{stdout} if $result->{status} == 0;
    return "";
  }
  return athinfo($self->{hostname}, "uptimesec");
}

############################################################################
# Perform post-reboot checks.
#
# @return <code>true</code> if the reboot finished successfully
##
sub checkReboot {
  my ($self) = assertMinArgs(1, @_);
  return $self->checkMegaRaidDevice();
}

######################################################################\
# Verify that the MegaRaid device exists.
#
# @return true if the megaraid device should exist and does
##
sub checkMegaRaidDevice {
  my ($self) = assertNumArgs(1, @_);
  my $device = getScamVar($self->{hostname}, 'MEGARAID');
  chomp($device);
  if ($device !~ /\S/) {
    return 1;
  }

  my $result = runCommand($self->{hostname}, "[ -e $device ]");
  if ($result->{status}) {
    $log->warn("Megaraid device was not set up after reboot");
    return 0;
  }

  return 1;
}

1;
