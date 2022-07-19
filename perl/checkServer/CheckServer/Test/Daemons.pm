##
# Check that required daemons are running
#
# $Id$
##
package CheckServer::Test::Daemons;

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
  my %daemons = keys(%DAEMONS);

  if ($self->isVirtual()) {
    delete $daemons{ntpd};
    delete $daemons{smartd};
  }

  #XXX: ntpd is not available in RHEL8, FEDORA32 and FEDORA33 anymore,
  #     we need to fix this at some point"
  if ($self->isRedHat()) {
    delete $daemons{ntpd};
    delete $daemons{cron};
    $daemons{crond} = 'crond';
  }

  foreach my $daemon (keys(%daemons)) {
    if (system("bash", "-c", "pgrep -x '^${daemon}\$' &>/dev/null") != 0) {
      if ($daemon ne "smartd") {
        $self->fail("Daemon $daemon not running");
        if (defined($daemons{$daemon})) {
          $self->addFixes("service $daemons{$daemon} restart");
        }
      }
    }
  }
}

1;

