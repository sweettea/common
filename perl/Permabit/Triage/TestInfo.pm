##
# Constants defined for triage and leaked machine assignments.
# These are mostly obsolete.
#
# @synopsis
#
#     use Permabit::Triage::TestInfo;
#
# $Id$
##
package Permabit::Triage::TestInfo;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Permabit::Triage::TestInfo::Implementation;

use base qw(Exporter);

our @EXPORT_OK = qw(
  %CODENAME_LOOKUP
  albireoPerfHosts
  vdoPerfHosts
);

our %EXPORT_TAGS = (
  albireo => [qw(
                 albireoPerfHosts
                 vdoPerfHosts
                )],
);

# cruisecontrol test suites
our @CRUISECONTROL_SUITES = qw(client mirror server);

# Jira project to codename string hash
our %CODENAME_LOOKUP = (
  ALB     => "ALBIREO_PROJECT_CODENAME",
  IMF     => "IMF_PROJECT_CODENAME",
  VDO     => "VDO_PROJECT_CODENAME",
  ALBSCAN => "ALBSCANLINUX_PROJECT_CODENAME",
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
    $IMPLEMENTATION = Permabit::Triage::TestInfo::Implementation->new();
  }

  return $IMPLEMENTATION;
}

#######################################################
# Return the list of albireo perf hosts.
#
# @return the albireo hosts, may be empty
##
sub albireoPerfHosts {
  return _getImplementation()->{albireoPerfHosts};
}

#######################################################
# Return the list of vdo perf hosts.
#
# @return the vdo hosts, may be empty
##
sub vdoPerfHosts {
  return _getImplementation()->{vdoPerfHosts};
}

1;
