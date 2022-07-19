##
# Check for write access to /u1 and /permabit/not-backed-up
#
# $Id$
##
package CheckServer::Test::CanWrite;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my @DIRECTORIES = qw(
  /u1
  /permabit/not-backed-up/tmp
  /tmp
);

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my $fileName;
  foreach my $dir (@DIRECTORIES) {
    if (!-d $dir) {
      $self->fail("$dir does not exist or cannot be accessed.");
      next;
    }

    # Make sure we can write files into the path
    $fileName = join('.', "$dir/checkServer", "checkCanWrite",
                     $self->hostname(), $$);
    my $fh = $self->open(">$fileName");
    if (!defined($fh)) {
      next;
    }

    $fh->close();
    if (!unlink($fileName)) {
      fail("Cannot remove $fileName: $ERRNO");
    }
  }
}

1;

