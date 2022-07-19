##
# Check for the existence of programs which should not be installed.
#
# $Id$
##
package CheckServer::Test::BadPrograms;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use CheckServer::Constants qw(
  @BAD_PROGRAMS
  @SYSTEM_BIN_DIRS
);

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  foreach my $dir (@SYSTEM_BIN_DIRS) {
    foreach my $prog (@BAD_PROGRAMS) {
      my $file = "$dir/$prog";
      if (-f $file) {
        $self->fail("$file exists");
        $self->addFixes("rm -f $file");
      }
    }
  }
}

1;

