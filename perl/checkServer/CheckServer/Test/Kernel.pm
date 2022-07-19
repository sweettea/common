##
# Check that the kernel is correct.
#
# $Id$
##
package CheckServer::Test::Kernel;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);
use Permabit::Utils qw(getScamVar);

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub skip {
  my ($self) = assertNumArgs(1, @_);
  return $self->isAnsible();
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my $kernel = $self->kernel();
  my @validKernels = $self->getValidKernels();
  if (scalar(grep { $kernel =~ /$_/ } @validKernels) == 0) {
    $self->fail("Bad kernel: $kernel is not one of "
                . join(' ', @validKernels));
  }
}

########################################################################
# Get the list of regexes to determine whether the currently installed kernel
# is valid.
##
sub getValidKernels {
  my ($self) = assertNumArgs(1, @_);
  if ($self->isSantiago()) {
    return '2.6.32-(71|279|358|431|504|573|642|696).*\.el6.x86_64';
  }

  if ($self->isMaipo()) {
    return '3.10.0-.*\.el7(|\.pbit[0-9]+).x86_64';
  }

  if ($self->isOotpa() || $self->isCentOS8()) {
    return '4.18.0-.*\.(|1.2.)el8(|_0).x86_64(|\+debug)';
  }

  if ($self->isPlow()) {
    return '5.14.0-.*.el9(|_0).x86_64(|\+debug)';
  }

  if ($self->isTwentySeven()) {
    return '4.*.fc27.x86_64';
  }

  if ($self->isTwentyEight()) {
    return '(4|5).*.fc28.x86_64';
  }

  if ($self->isTwentyNine()) {
    return '(4|5).*.fc29.x86_64';
  }

  if ($self->isThirty()) {
    return '5.*.fc30.x86_64';
  }

  if ($self->isThirtyOne()) {
    return '5.*.fc31.x86_64';
  }

  if ($self->isThirtyTwo()) {
    return '5.*.fc32.x86_64';
  }

  if ($self->isThirtyThree()) {
    return '5.*.fc33.x86_64';
  }

  if ($self->isThirtyFour()) {
    return '5.*.fc34.x86_64';
  }

  if ($self->isThirtyFive()) {
    return '5.*.fc35.x86_64';
  }

  if ($self->isThirtySix()) {
    return '5.*.fc36.x86_64';
  }

  if ($self->isRawhide()) {
    # Since Fedora Rawhide's kernel changes so frequently
    # we can only check basic formatting.
    return '\d+\.\d+\..*fc\d{2}\.x86_64';
  }

  $self->fail("Unable to resolve the distro that this server is running!\n");
}

1;

