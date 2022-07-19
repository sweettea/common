##
# Constants defined for triage and leaked machine assignments.
#
# @synopsis
#
#     use Permabit::Triage::TestInfo;
#
#     my $jiraComponent = $TEST_INFO{$suiteName}{component};
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
  %COMPONENTS_LOOKUP
  %TEST_INFO
  %TRIAGE_INFO
  albireoPerfHosts
  vdoPerfHosts
);

our %EXPORT_TAGS = (
  albireo => [qw(
                 albireoPerfHosts
                 vdoPerfHosts
                )],
);

# default Jira project key
our $JIRAPROJ = 'OPS';

# cruisecontrol test suites
our @CRUISECONTROL_SUITES = qw(client mirror server);

# A map from component names (some legacy) to the JIRA project key
# of the project responsible for triage of the component.
our %TRIAGE_INFO = (
  'Platform'             => 'OPS',
  'QA'                   => 'OPS',
  'DevOps'               => 'OPS',
  'Test'                 => 'ALB',
  'Documentation'        => 'ALB',
  'Utils'                => 'ALB',
  'Data Set'             => 'ALB',
  'SDK (Software)'       => 'ALB',
  'Software'             => 'VDO',
  'Albireo'              => 'ALB',
  'FAI'                  => 'OPS',
  'Perl'                 => 'VDO',
  'Modelling'            => 'OPS',
  'Grapher'              => 'OPS',
);

# Albireo specific jira components
my @ALB_COMPONENTS = (
  'Test',
  'Data Set',
  'Documentation',
  'SDK (Software)',
);

# VDO specific jira components
my @VDO_COMPONENTS = (
  'Software',
);

# IMF specific jira components
my @IMF_COMPONENTS = (
  'FAI',
  'Modelling',
  'Perl',
);

# Jira project to codename string hash
our %CODENAME_LOOKUP = (
  ALB     => "ALBIREO_PROJECT_CODENAME",
  IMF     => "IMF_PROJECT_CODENAME",
  VDO     => "VDO_PROJECT_CODENAME",
  SANBLOX => "SANBLOX_PROJECT_CODENAME",
  ALBSCAN => "ALBSCANLINUX_PROJECT_CODENAME",
);

# Jira project to components hash
our %COMPONENTS_LOOKUP = (
 ALB => \@ALB_COMPONENTS,
 IMF => \@IMF_COMPONENTS,
 VDO => \@VDO_COMPONENTS,
);

# Test info
our %TEST_INFO = (
  AlbireoTest =>
  {
    component           => 'SDK (Software)',
    project             => 'ALB',
    namePattern         => 'AlbireoTest::(.*).log',
    prefix              => 'AlbireoTest::',
    runLogDirs          => [qr/Albireo\w*_Tests/],
  },
  ModellingTest =>
  {
    component           => 'Modelling',
    project             => 'IMF',
    namePattern         => 'ModellingTest::(.*).log',
    prefix              => 'ModellingTest::',
    runLogDirs          => [qr/Modelling\w*_Tests/],
  },
  Cunit =>
  {
    component           => 'SDK (Software)',
    project             => 'ALB',
    prefix              => '',
    namePattern         => 'AlbireoTest::([^:]+::[^:]+)',
    runLogDirs          => ['Albireo_Cunit_Tests'],
  },
  Cunit_lcov =>
  {
    component           => 'SDK (Software)',
    project             => 'ALB',
    prefix              => '',
    namePattern         => '[run|capture|html]_(.*).log',
    runLogDirs          => ['Albireo_Cunit_Lcov_Tests'],
  },
  LabTest =>
  {
    component           => 'FAI',
    project             => 'IMF',
    namePattern         => 'LabTest::(.*).log',
    prefix              => 'LabTest::',
    runLogDirs          => ['Lab_Tests'],
  },
  PerlTest =>
  {
    component           => 'Perl',
    project             => 'IMF',
    namePattern         => 'testcases::(.*).log',
    prefix              => 'testcases::',
    runLogDirs          => ['Perl_Tests'],
  },
  VDOTest =>
  {
    component           => 'Software',
    project             => 'VDO',
    namePattern         => 'VDOTest::(.*).log',
    prefix              => 'VDOTest::',
    runLogDirs          => [qr/VDO\w*_Tests/],
  },
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
