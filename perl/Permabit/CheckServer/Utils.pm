##
# A set of utility methods for CheckServer/checkServer.pl.
#
# @synopsis
#
#    use CheckServer::Utils qw(XXXX);
#
#    my @classValues = getClassArray('className', 'VALUES');
#
# @description
#
# This class implements class methods which provide environment-specific
# implementations.
#
# $Id$
##
package Permabit::CheckServer::Utils;

use strict;
use warnings FATAL => qw(all);
use Carp;
use English qw(-no_match_vars);
use Storable qw(dclone);

use Permabit::Assertions qw(
  assertMinMaxArgs
  assertNumArgs
);
use Permabit::CheckServer::Utils::Implementation;

use base qw(Exporter);

our @EXPORT_OK = qw(
  dnsConfiguration
  fqdnSuffix
);

# Environment-specific implementation.
our $IMPLEMENTATION;

############################################################################
# Return the instance which provides the Configured controlled functionality.
#
# @return the Configured functional instance
##
sub _getImplementation {
  if (!defined($IMPLEMENTATION)) {
    $IMPLEMENTATION = Permabit::CheckServer::Utils::Implementation->new();
  }

  return $IMPLEMENTATION;
}

###########################################################################
# Return the expected DNS configuration.
#
# @return The DNS configuration, may be undefined
##
sub dnsConfiguration {
  return _getImplementation()->{dns};
}

###########################################################################
# Return the suffix of a fully-qualified host name.
#
# @return The fqdn suffix, may be undefined
##
sub fqdnSuffix {
  return _getImplementation()->{hostname}->{fqdnSuffix};
}

1;
