##
# Make sure that no symlinks exist within any of @NO_SYMLINK_DIRS.
#
# $Id$
##
package CheckServer::Test::BadDirs;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use CheckServer::Constants qw(
  @NO_SYMLINK_DIRS
  @OK_SYMLINK_FILES
);

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
  foreach my $dir (@NO_SYMLINK_DIRS) {
    if (-l $dir) {
      $self->fail("Symlink $dir not allowed");
      $self->addFixes("rm $dir");
    } elsif (-d $dir) {
      foreach my $symlink ($self->runCommand("find $dir -type l")) {
        if (!grep { $symlink eq $_ } @OK_SYMLINK_FILES) {
          $self->fail("Symlink $symlink not allowed");
          $self->addFixes("rm $symlink");
        }
      }
    }
  }
}

1;

