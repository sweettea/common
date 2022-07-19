##
# Check the global LVM configuration.
#
# $Id$
##
package CheckServer::Test::LVMConf;

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
  if (grep({ /verbose\s*=\s*[123]/ } $self->readFileOrAbort($LVM_CONF))) {
    $self->fail("lvm configured with bad verbose level");
    $self->addFixes("sed -i 's/verbose = [123]/verbose = 0/' $LVM_CONF");
  }
}

1;
