##
# Clean up the Python installation after some VDO testing.
#
# $Id$
##
package CheckServer::Test::PythonHacks;

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
sub test {
  my ($self) = assertNumArgs(1, @_);
  my $command = qq/python -c 'import sys; print(" ".join(sys.path))'/;
  foreach my $dir (split(/\s+/, $self->runCommand($command))) {
    foreach my $suffix ("py", "pyc") {
      my $badFile = "$dir/vdoInstrumentation.$suffix";
      if (-e $badFile) {
        $self->fail("found Python module $badFile");
        $self->addFixes("rm $badFile");
      }
    }
  }
}

1;

