##
# Check that we're in the correct timezone (EDT)
#
# XXX: /etc/localtime doesn't exist (or isn't a symlink) on RH distros.
#
# $Id$
##
package CheckServer::Test::TimeZone;

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
sub skip {
  my ($self) = assertNumArgs(1, @_);
  return $self->isRedHat();
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my $correctZone = "/usr/share/zoneinfo/America/New_York";
  my $symlink     = "/etc/localtime";
  my $current     = readlink($symlink);
  my $makeLink    = "rm -f $symlink ; ln -s $correctZone $symlink";
  my $rmLink      = "rm $symlink";

  if (! -l $symlink) {
    $self->fail("$symlink is not a symlink (or does not exist)");
    $self->addFixes($makeLink);
    return;
  }

  if ($correctZone ne $current) {
    $self->fail("I'm in the wrong time zone: $current");
    $self->addFixes($rmLink, $makeLink);
  }
}

1;

