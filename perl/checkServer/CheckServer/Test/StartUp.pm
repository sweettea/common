##
# Check lists of packages which should not start at boot.
#
# $Id$
##
package CheckServer::Test::StartUp;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use CheckServer::Constants;

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  foreach my $service (grep({ $self->checkStartOnBoot($_); }
                            @SERVICES_NOT_STARTED_AT_BOOT)) {
    $self->fail("$service configured to start on boot");
    $self->rebuildFromMach("svc_$service", 1);
  }
}

1;

