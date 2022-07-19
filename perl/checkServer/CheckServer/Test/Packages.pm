##
# Check for installed packages that shouldn't be there.
#
# $Id$
##
package CheckServer::Test::Packages;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;
use YAML qw(LoadFile);

use Permabit::Assertions qw(assertNumArgs);
use Permabit::PlatformUtils qw(getPkgBundle);

use CheckServer::Constants;

use base qw(CheckServer::AsyncTest);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub skip {
  my ($self) = assertNumArgs(1, @_);
  # XXX: Old support for non-RH like things has been removed.
  return !$self->isRedHat();
}

########################################################################
# Generate a hash of installed packages.
##
sub getInstalledPackages {
  my ($self) = assertNumArgs(1, @_);

  # generate the hash of already installed packages
  my $command = 'rpm -qa --qf \'%{Name}.%{arch}:%{Version}-%{Release}\n\'';
  return { map({
                /^(.*):(.*)$/;
               } grep {
                 $_ !~ /gpg-pubkey|beaker-/;
               } $self->assertCommand($command))
         };
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  if (!-e "/etc/required_packages") {
    $self->fail("No /etc/required_packages");
    return;
  }

  my $required = LoadFile("/etc/required_packages");
  if ((ref($required) ne 'HASH') || (keys(%$required) == 0)) {
    $self->fail("Incorrect format for /etc/required_packages file");
  }

  my $installed = $self->getInstalledPackages();
  my @forbidden = grep { !exists($required->{$_}) } keys(%{$installed});
  my $beakerExclusionRE = qr/^gpm-libs|vim-(common|enhanced)/;
  my @removePackages = map {
    # Avoid having to check this again in the version check below
    delete $installed->{$_};
    $_;
  } grep {
    exists($installed->{$_});
  } grep {
    # We exclude some packages here because permabit lab machines require them
    # but beaker infrastructure tasks install them on beaker systems and we
    # need to ignore them.
    $_ !~ $beakerExclusionRE;
  } @forbidden;

  if (@removePackages) {
    my $toRemove = join(' ', @removePackages);
    $self->fail("packages $toRemove installed");
    if ($self->isCentOS() || $self->isRHEL()) {
      $self->addFixes("yum remove -y $toRemove");
    } elsif ($self->isFedora()) {
      $self->addFixes("dnf remove -y $toRemove");
    }
  }

  # Check version mismatch from installed and /etc/required_packages [OPS-4684]
  foreach my $package (grep { $_ !~ $beakerExclusionRE } keys(%{$installed})) {
    my $version          = $required->{$package};
    my $installedVersion = $installed->{$package};
    if ($version eq $installedVersion) {
      next;
    }

    $self->fail("$package version mismatch: "
                . "required $version got $installedVersion");
    if ($self->isCentOS() || $self->isRHEL()) {
      $self->addFixes("yum remove -y $package");
      $self->addFixes("yum install -y $package");
    } elsif ($self->isFedora()) {
      $self->addFixes("dnf remove -y $package");
      $self->addFixes("dnf install -y $package");
    }
  }

  my @missingPackages = grep { !exists($installed->{$_}) } keys(%{$required});
  if (@missingPackages) {
    my $missing = join(' ', @missingPackages);
    $self->fail("Required package(s) $missing not installed");
    if ($self->isCentOS() || $self->isRHEL()) {
      $self->addFixes("yum install -y $missing");
    } elsif ($self->isFedora()) {
      $self->addFixes("dnf install -y $missing");
    }
  }
}

1;

