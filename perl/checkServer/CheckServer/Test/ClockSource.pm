##
# Check that the kernel is using the correct clocksource.
#
# $Id$
##
package CheckServer::Test::ClockSource;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub skip {
  my ($self) = assertNumArgs(1, @_);
  return ($self->isVirtual() || $self->isBeaker());
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my $clockSource = $self->getClocksource();
  if ($clockSource eq 'tsc') {
    return;
  }

  $self->fail("clocksource is incorrect: expected 'tsc', got '$clockSource'");
  $self->rebuildFromMach("configGrub");
}

1;
