##
# Check that the perl.yaml config file is present.
#
# $Id$
##
package CheckServer::Test::PerlConfig;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my $PERL_CONFIG_FILE = '/etc/permabit/perl.yaml';
########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  if (! -r $PERL_CONFIG_FILE) {
    $self->fail("$PERL_CONFIG_FILE missing");
  }
}


1;

