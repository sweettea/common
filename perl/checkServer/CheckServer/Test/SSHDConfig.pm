##
# Check that sshd DEBUG is not turned on in the lab.  This caused
# major problems see @53529, RT/36032.
#
# $Id$
##
package CheckServer::Test::SSHDConfig;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use CheckServer::Constants;

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my $SSHD_CONFIG = '/etc/ssh/sshd_config';

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my @lines = grep { /LogLevel.*INFO/ } $self->readFileOrAbort($SSHD_CONFIG);
  if (scalar(@lines) != 1) {
    $self->fail("LogLevel not set to INFO in /etc/ssh/sshd_config");
    $self->rebuildFromMach("sshd_config");
  }
}

1;

