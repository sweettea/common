#!/usr/bin/perl
# -*-cperl-*-

##
# Check if a server is ready to be released back to the general pool.
#
# @synopsis
#
# checkServer.pl [--fix] [--user USERNAME] [--force] [-n] [--verbose] [--noRun]
#
# @level{+}
#
# @item B<--fix>
#
# Fix this machine instead of printing what's wrong with it.  Must be
# run as root.
#
# @item B<--user USERNAME>
#
# Perform checks on behalf of USERNAME.
#
# @item B<--force>
#
# USE WITH CAUTION: override the RSVP check. With this option, machines
# can be fixed even when not owned by the current user. It's also the only
# way to run fixes on desktop machines.
#
# @item B<-n>
#
# Describe what fixes would have been performed, without running them.
#
# @item B<--verbose>
#
# Display the names of the tests that are run as they are being run.
#
# @item B<--noRun>
#
# Display the names of the tests that would be run, but don't actually run
# them.
#
# @item B<--debug>
#
# Display debugging messages.
#
# @item B<--testRegexp>
#
# A regular expression used to filter which checks to perform. Should only be
# used for debugging.
#
# @item B<--help>
#
# Print this message and exit.
#
# @level{-}
#
# @description
#
# Check a server for the most common reasons tests are not able to run.
#
# Doesn't check for processes on the machine, this is handled separately by
# the rsvp process (Permabit/RSVP.pm) so that it can do per-user checks.
#
# You should test your changes to this file by:
#   cd src/perl/Permabit ; ./runtests.pl CheckServer_t1
#
# $Id$
##
use strict;
use warnings FATAL => qw(all);

use Carp qw(croak);
use English qw(-no_match_vars);
use File::Spec;
use Getopt::Long;
use Log::Log4perl;

use FindBin;
use lib "${FindBin::RealBin}/../lib";
use lib "${FindBin::RealBin}";

use Pdoc::Generator qw(pdoc2help pdoc2usage);

use Permabit::Assertions qw(assertNumArgs);

BEGIN {
}

use CheckServer::Framework;

my @ENVIRONMENT_VARIABLES = qw(
  PRSVP_HOST
  PERMABIT_PERL_CONFIG
);

# The following is used as a global marker to ensure that something
# happens even if something bad happens
my $loaded;
END {
  if (!$loaded) {
    # Make sure this prints FAILURE even if it cannot run
    print "FAILURE\nUnable to run $0\n";
  }
}

main();
exit(0);

######################################################################
# Check that this server is ready to be released
##
sub main {
  if (($UID != 0) || ($EUID != 0)) {
    my @env = map({
                   "$_=$ENV{$_}"
                  } grep {
                    exists($ENV{$_})
                  } @ENVIRONMENT_VARIABLES);
    exec('sudo', @env, $0, @ARGV);
    die("Failed to re-execute as root");
  }

  $loaded = 1;
  my $config = parseArgs();
  initializeLogger($config);
  CheckServer::Framework->new(%{$config})->run();
}

######################################################################
# Parse command line arguments.
#
# @return The parsed arguments
##
sub parseArgs {
  my $config = {};
  my $script = File::Spec->catfile($FindBin::RealBin, $FindBin::RealScript);
  if (!GetOptions($config,
                  qw(debug!
                     fix!
                     force!
                     noRun!
                     testRegexp=s
                     timestamps!
                     user=s
                     verbose!
                     dryRun!
                     n!
                     help!))) {
    pdoc2usage($script);
  }

  if ($config->{help}) {
    pdoc2help($script);
  }

  if ($config->{n}) {
    $config->{dryRun} = 1;
  }

  if ($config->{dryRun} && $config->{fix}) {
    print STDERR "Use -n or --fix, but not both.\n";
    exit(1);
  }

  return $config;
}

######################################################################
# Initialize the logger
#
# @param config  The config from the command line
##
sub initializeLogger {
  my ($config) = assertNumArgs(1, @_);

  my $logLevel;
  if ($config->{debug}) {
    $logLevel = 'DEBUG';
  } elsif ($config->{verbose} || $config->{noRun}) {
    $logLevel = 'INFO';
  } else {
    $logLevel = 'WARN';
  }

  my $layout    = ($config->{timestamps} ? '%d %m%n' : '%m%n');
  my $logConfig = << "EOCONFIG";
log4perl.rootLogger = $logLevel, Screen

# Log to STDERR
log4perl.appender.Screen        = Log::Log4perl::Appender::Screen
log4perl.appender.Screen.stderr = 0
log4perl.appender.Screen.layout = Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern = $layout
EOCONFIG

  Log::Log4perl->init(\$logConfig);
}
