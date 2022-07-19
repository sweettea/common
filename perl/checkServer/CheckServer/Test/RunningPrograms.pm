##
# Check if various of our programs are running that shouldn't be.
#
# $Id$
##
package CheckServer::Test::RunningPrograms;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use CheckServer::Constants;

use base qw(CheckServer::AsyncTest);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my $foundRunningProgram = 0;
  foreach my $prog (@BAD_PROGRAMS) {
    if (system("pgrep -x $prog >/dev/null") == 0) {
      $self->fail("$prog is running");
      $self->addFixes("pkill -x $prog");
      $foundRunningProgram = 1;
    }
  }

  # Check for system processes that shouldn't be running
  foreach my $prog (@BAD_PROCESSES) {
    # Search the command line with pgrep -f because valgrind changes
    # the process name unlike the programs in @BAD_PROGRAMS
    if (system("pgrep -f '^$prog' >/dev/null") == 0) {
      $self->fail("$prog is running");
      $self->addFixes("kill `pgrep -f '^$prog'`");
      $foundRunningProgram = 1;
    }
  }

  # If we found any running programs, allow time for them to die
  if ($foundRunningProgram) {
    $self->addFixes("sleep 2");
  }
}

1;

