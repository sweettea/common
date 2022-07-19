##
# Make sure loop devices aren't left configured after tests.
#
# $Id$
##
package CheckServer::Test::LoopDevices;

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
  return $self->isAnsible();
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  foreach my $line ($self->assertCommand('losetup -a')) {
    my $device = $line;
    $device =~ s/:.*$//;
    if ($line =~ m,/home/big_file,) {
      next;
    }

    $self->fail("Loop device $device found");
    $self->addFixes("sudo losetup -d $device");
  }
}

1;
