##
# Check that DNS is configured correctly.
#
# $Id$
##
package CheckServer::Test::DNS;

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
sub skip {
  my ($self) = assertNumArgs(1, @_);
  return $self->isAnsible();
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  my $conf = '/etc/resolv.conf';

  my %patterns = (search => qr/^(?:search|domain) permabit\.com/,
                  ns1    => qr/^nameserver\s+10.19.117.1/,
                  ns2    => qr/^nameserver\s+10.19.117.2/);
  my $fh = $self->openOrAbort($conf);
  while (my $line = $fh->getline()) {
    my @patterns = keys(%patterns);
    if (scalar(@patterns) == 0) {
      $fh->close();
      last;
    }

    foreach my $pattern (@patterns) {
      if ($line =~ /$patterns{$pattern}/) {
        delete $patterns{$pattern};
      }
    }
  }

  if (%patterns) {
    $self->fail("Invalid $conf. Couldn't find lines that matched:\n\t"
                . join("\n\t", values(%patterns)));
    $self->addFixes("dhclient");
  }
}

1;

