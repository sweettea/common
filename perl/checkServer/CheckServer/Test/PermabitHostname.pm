##
# Check that the hostname is fully-qualified.
#
# $Id$
##
package CheckServer::Test::PermabitHostname;

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
  return ($self->isVagrant() || $self->isBeaker());
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my $hostname = $self->hostname();
  if ($hostname !~ /\.permabit\.com$/) {
    $self->fail("Hostname not fully qualified");
    $hostname = "$hostname.permabit.com";
    $self->addFixes("echo $hostname > /etc/hostname", "hostname $hostname");
  }
}

1;
