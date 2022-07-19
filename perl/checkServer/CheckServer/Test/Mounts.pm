##
# Check that /var/crash is empty.
#   under --fix: Moves all crash files to a directory in
#                /permabit/not-backed-up
#
# $Id$
##
package CheckServer::Test::Mounts;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);
use Permabit::Constants;

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  foreach my $mount ($self->assertCommand('mount')) {
    if ($mount =~ m,on (/(mnt|u1)/\S+)\s,) {
      $mount = $1;
      $self->fail("$mount mounted");
      $self->addFixes("umount -f $mount");
    }
  }
}

1;
