##
# A representation of the host being checked.
#
# $Id$
##
package CheckServer::Host;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use File::Basename;
use Log::Log4perl;

use Permabit::Assertions qw(
  assertMinArgs
  assertMinMaxArgs
  assertNumArgs
);
use Permabit::Constants;
use Permabit::PlatformUtils;
use Permabit::SystemUtils qw(runSystemCommand);
use Permabit::Triage::TestInfo qw(:albireo);
use Permabit::Utils qw(getScamVar);

use CheckServer::Constants;

use base qw(Permabit::Configured CheckServer::Delegate);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my %SCAM_QUERIES = map({ ($_, 1) } qw(ansible
                                      beaker
                                      vagrant));

######################################################################
# Get the name of the key under which the caller's result would be cached.
##
sub _getCachedName {
  return (caller(1))[3];
}

######################################################################
# Get a parameter defined in the configuration.
#
# @param  name  The name of the parameter
# @oparam default  A default value to return if the parameter was not defined
#         inthe configuration; defaults to undef
#
# @return The configured value of the named parameter
##
sub getParameter() {
  my ($self, $parameter, $default) = assertMinMaxArgs([undef], 2, 3, @_);

  return $self->{$parameter} // $default;
}

######################################################################
# Check whether our hostname or short hostname is in a specified list.
#
# @param short If short, use the short hostname.
# @param list  The list to check
##
sub hostnameInList {
  my ($self, $short, @hosts) = assertMinArgs(2, @_);
  my $name = ($short ? $self->shortHostname() : $self->hostname());
  return scalar(grep { $_ eq $name } @hosts);
}

######################################################################
# Check whether our hostname matches a regex.
#
# @param regex The regex to check
##
sub hostnameMatches {
  my ($self, $regex) = assertNumArgs(2, @_);
  my $name = $self->hostname();
  return ($name =~ $regex);
}

######################################################################
# Are we an albireo PMI machine?
##
sub isAlbPerf {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()}
          //= $self->hostnameInList(1, albireoPerfHosts()));
}

######################################################################
# Check if this host is a development VM box
##
sub isDevVM {
  my ($self) = assertNumArgs(1, @_);
  # Includes the condition for Vagrant to identify systems that were created
  # before DEVVM was added as a SCAM variable.
  return ($self->{_getCachedName()}
          //= ((!!getScamVar("DEVVM")) || $self->isVagrant()));
}

######################################################################\
# Are we a farm?
##
sub isFarm {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()}
          //= ($self->isJFarm()
               || $self->isPFarm()
               || (getScamVar('FARM') eq 'yes')));
}

######################################################################
# Check if this host is a jfarm class machine
##
sub isJFarm {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()} //= $self->hostnameMatches(qr/^jfarm-/));
}

######################################################################
# Check if this host is a pfarm class machine
##
sub isPFarm {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()} //= $self->hostnameMatches(qr/^pfarm-/));
}

######################################################################
# Check if this host is a nighly/resource class machine
##
sub isResource {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()} //= $self->hostnameMatchs(/^resource-/));
}

######################################################################
# Check if this host is a VDO PMI machine.
##
sub isVDOPerf {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()}
          //= ($self->hostnameInList(1, vdoPerfHosts())));
}

######################################################################
# Check if this host is a vfarm class machine
##
sub isVFarm {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()} //= $self->hostnameMatches(qr/^vfarm-/));
}

######################################################################\
# Are we a virtual host?
##
sub isVirtual {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()}
          //= ($self->isVFarm()
               || $self->isVagrant()
               || $self->detectVirtual()));
}

######################################################################\
# Attempt to detect if this host is virtual when the simple checks are
# indeterminate. This method should only be called from isVirtual().
##
sub detectVirtual {
  my ($self) = assertNumArgs(1, @_);
  my ($detectedVirt) = $self->runCommand('systemd-detect-virt');
  # Empty if not installed; "none" if bare metal.
  if ($detectedVirt eq "none") {
    return 0;
  }

  if ($detectedVirt ne "") {
    # kvm, vmware, qemu, ...
    return 1;
  }

  if ($self->machine eq 'x86_64') {
    return 0;
  }

  my $productName = $self->runCommand('dmidecode -s system-product-name');
  return (($productName eq "KVM")
          || ($productName eq "VMware Virtual Platform")
          || ($productName eq "VirtualBox"));
}

########################################################################
# Is this host running RHEL?
##
sub isRHEL {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()}
          //= Permabit::PlatformUtils::isRedHat());
}

########################################################################
# Is this host running a RedHat related OS (RHEL, CentOS, or Fedora)?
##
sub isRedHat {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()}
          //= ($self->isCentOS()
               || $self->isFedora()
               || $self->isRHEL()));
}

######################################################################
# Should this host be running ntp?
##
sub isNTP {
  my ($self) = assertNumArgs(1, @_);
  return !$self->isVirtual();
}

########################################################################
# Get the hostname.
##
sub hostname {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()} //= _chomp(`hostname`));
}

########################################################################
# Get the name of the kernel.
##
sub kernel {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()} //= _chomp(`uname -r`));
}

########################################################################
# Get the machine type (ala uname -m).
##
sub machine {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()} //= _chomp(`uname -m`));
}

########################################################################
# Get the short hostname.
##
sub shortHostname {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()}
          //= (split(/\./, $self->hostname()))[0]);
}

######################################################################
# Get the RSVP server's belief about the classes for this host. Handles
# a host with no class info successfully.  The host may legitimately
# have no classes or be in MAINTENANCE or not be in RSVP.
##
sub getRSVPClasses {
  my ($self) = assertNumArgs(1, @_);
  my $key = _getCachedName();
  if (!exists($self->{$key})) {
    my $name = $self->shortHostname();
    my $rsvp = Permabit::RSVP->new();
    my @rsvpClasses;
    eval {
      @rsvpClasses = $rsvp->getClassInfo($name);
      if ($rsvp->isInMaintenance($name)) {
        push(@rsvpClasses, 'MAINTENANCE');
      }
    };

    $self->{$key} = { map({ ($_, 1) } @rsvpClasses) };
  }

  return $self->{$key};
}

######################################################################
# Check whether this host has RSVP classes.
#
# @return true if the host has RSVP classes
##
sub hasRSVPClasses {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{_getCachedName()}
          //= scalar(keys(%{$self->getRSVPClasses()})));
}

######################################################################
# Check whether this host in in an RSVP class.
#
# @param class  The class to check
#
# @return true if the host is in the specified class
##
sub inRSVPClass {
  my ($self, $class) = assertNumArgs(2, @_);
  my $classes = $self->getRSVPClasses();
  return $classes->{$class};
}

######################################################################
# Get the physical device associated with the given partition
#
# @param volume The volume to get the device for
#
# @return The base device name or nothing if unable to determine it
##
sub getPartitionDevice {
  my ($self, $volume) = assertNumArgs(2, @_);
  my $device = $self->{partitionDevice}{$volume};
  if (defined($device)) {
    return $device;
  }

  my $dfOutput = $self->runCommand("df -P $volume");
  if ($dfOutput =~ m|/dev/([sh]d[a-z]+\d+).*$volume|) {
    return $self->{partitionDevice}{$volume} = $1;
  }

  # Get a regex compatible pattern containing the possible VG names for
  # a farm's scratch volume for testing.
  my $scratchVGPattern = $self->getScratchVGPattern();
  # Attempt to get the device name of the volume
  if ($dfOutput =~ m#(/dev/mapper/($scratchVGPattern)-scratch)#) {
    # Derefernce the logical volume's device mapper link
    my $match = $1;
    return $self->{partitionDevice}{$volume}
      = basename($self->runCommand("readlink $match"));
  }

  return undef;
}

#####################################################################
#
# @return the pattern containing the possible VG names
##
sub getScratchVGPattern {
  my ($self) = assertNumArgs(1, @_);
  # Some RHEL and Fedora configurations seem to incorporate the distro
  # name and host name. Some use an alphanumeric string.
  return ($self->{_getCachedName()} //= join('|',
					     _getUniqueScratchVGNames(),
					     'scratch',
					     'vg_xvd[a-z]2',
					     'rhel_[a-z0-9_-]*',
					     'fedora_[a-z0-9_-]*',
					     '[a-z0-9]{12}'));
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
  map({ _replace(_chomp(IO::File->new($_)->getline), ':', '', 'g') }
      grep({ -e $_ }
           map({ "$_/address" }
               grep({ !/.*\/lo$/ }
                    glob('/sys/class/net/*')))));
}

######################################################################
# Get the physical size of the given partition.
#
# @param partition  The partition to get the physical size of
#
# @return The size of the given partition
##
sub getPartitionSize {
  my ($self, $partition) = assertNumArgs(2, @_);
  foreach my $line (IO::File->new('/proc/partitions')->getlines()) {
    if ($line =~ /\s+\d+\s+\d+\s+(\d+)\s+$partition/) {
      return $1;
    }
  }

  die("Couldn't determine $partition size");
}

######################################################################
# Get the size available in the given partition.  Returns -1 if unable to
# determine available size.
#
# XXX: This should be rewritten using Filesys::DiskSpace when it is
# installed
##
sub getPartitionAvailableSize {
  my ($self, $partition) = assertNumArgs(2, @_);
  my $df = $self->runCommand("df -P -k $partition");
  if ($df =~ m'/dev/\S+\s+\d+\s+\d+\s+(\d+)\s+\d+%\s+/.*$') {
    return $1 * 1024;
  }

  die("Couldn't determine $partition available size");
}

######################################################################
# Get the amount of memory.
#
# @return amount of memory (in kB)
##
sub getMemory {
  my ($self) = assertNumArgs(1, @_);
  my $size = $self->runCommand("grep MemTotal /proc/meminfo");
  $size =~ s/\D*(\d+).*/$1/;
  return _chomp($size);
}

######################################################################
# Get the grub version of this host
#
# @return the version of grub, either 1 or 2
##
sub getGrubVersion {
  my ($self) = assertNumArgs(1, @_);
  my $key = _getCachedName();
  if (exists($self->{$key})) {
    return $self->{$key};
  }

  # TODO: use KernelUtils instead of doing this all by itself.  For now, will
  # add grub version 2 support.
  #
  # grub version 1 does not have an "update-grub" command, so if it's there
  # (and it's executable) it's definitely at least grub version 2.
  my $which = map { chomp($_) } $self->runCommand('which update-grub');
  if (($which =~ m/update-grub/) && (-x $which) && (-f "/etc/default/grub")) {
    return $self->{$key} = 2;
  } elsif (-d "/boot/grub2") {
    # On RHEL 7.5 Vagrant boxes we don't have update-grub but it is v2.
    return $self->{$key} = 2;
  } else {
    # Otherwise this host appears to be using grub version 1
    return $self->{$key} = 1;
  }
}

######################################################################
# Check whether a given package starts on boot and kick an error if so
#
# @param  service  Service which should not start at boot time
#
# @return true if the service will start on boot
##
sub checkStartOnBoot {
  my ($self, $service) = assertNumArgs(2, @_);
  my @files = glob("/etc/rc?.d/S??$service");
  return scalar(@files);
}

######################################################################
# Generate the commands for rebuilding a file from /permabit/mach.
#
# @param  file       The file to rebuild
# @oparam noVarConf  Set to true if /var/conf should not be consulted, defaults
#                    to false
##
sub rebuildFromMach {
  my ($self, $file, $noVarConf) = assertMinMaxArgs(2, 3, @_);
  # By default, this is a no-op. This should be overridden in environments
  # which have /permabit/mach.
}

######################################################################
# Check if this host has a specified command.
#
# @param command  The name of the command we want
#
# @return true if the command exists
##
sub hasCommand {
  my ($self, $command) = assertNumArgs(2, @_);
  if (!exists($self->{commands}{$command})) {
    chomp(my $cmd = $self->runCommand("which $command 2>/dev/null"));
    $self->{properties}{$command} = (($cmd =~ /$command/) && (-x $cmd));
  }

  return $self->{properties}{$command};
}

########################################################################
# A version of chomp which returns the modified string instead of the number
# of characters which were removed.
#
# @param string  The string to chomp
#
# @return The chomped string
##
sub _chomp {
  my ($string) = assertNumArgs(1, @_);
  chomp($string);
  return $string;
}

########################################################################
# Do a regex replace on a string and return the modified string.
#
# @param string       The string to modify
# @param re           The regex to match
# @param replacement  The replacement
# @param regex flags  Any regex flags to apply
##
sub _replace {
  my ($string, $re, $replacement, $flags) = assertMinMaxArgs([''], 3, 4, @_);
  eval("'$string' =~ s/$re/$replacement/$flags");
  return $string;
}

########################################################################
# Check whether a method is defined in PlatformUtils.
##
sub _isPlatformUtil {
  my ($method) = assertNumArgs(1, @_);
  foreach my $export (@Permabit::PlatformUtils::EXPORT_OK) {
    if ($export eq $method) {
      return 1;
    }
  }

  return 0;
}

########################################################################
# Run a command and return its output. stderr will be logged.
#
# @param  command       The command to run
# @oparam continuation  Any number of additional parts of the command
#
# @return The output of the command
##
sub runCommand {
  my ($self, @command) = assertMinArgs(2, @_);
  my $stdout = runSystemCommand(join(' ', @command))->{stdout};
  return (wantarray ? split("\n", $stdout) : $stdout);
}

########################################################################
sub load {
  my ($self, $method, $install) = assertNumArgs(3, @_);
  my $property;
  if (exists($self->{$method})) {
    $property = $method;
  } elsif ($method =~ /^is([A-Z].*)$/) {
    $property = lc($1);
    if ($SCAM_QUERIES{$property}) {
      $self->{$property} = !!getScamVar(uc($property));
    } elsif (_isPlatformUtil($method)) {
      $self->{$property} = eval("Permabit::PlatformUtils::$method()");
    } elsif ($property =~ /.farm$/) {
      $self->{$property} = $self->hostnameMatches(/^$property-/);
    } else {
      $property = undef;
    }
  } elsif (_isPlatformUtil($method)) {
    $property = $method;
    $self->{$property} = eval("Permabit::PlatformUtils::$method()");
  }

  if (defined($property)) {
    no strict 'refs';
    *{$install} = sub {
      my ($self) = assertNumArgs(1, @_);
      return $self->{$property};
    };

    return 1;
  }

  return 0;
}

1;

