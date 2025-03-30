##
# C<Permabit::Triage> provides utilities to make some triage tasks easier
#
# @synopsis
#
#        use Permabit::Triage::Utils qw(getOwnerMoveToMaint);
#
#        getOwnerMoveToMaint($params{host}, $rsvpObj);
#
# @description
#
# "Permabit::Triage::Utils" provides utility methods for triage tasks like
# moving machines that nightly couldn't clean up into maintenance.
#
# $Id$
##
package Permabit::Triage::Utils;

use strict;
use warnings FATAL => qw(all);
use autodie qw(open close);

use Carp qw(confess);
use English qw(-no_match_vars);
use File::Temp qw(tempdir);
use FindBin;
use Log::Log4perl;
use Permabit::Assertions qw(
  assertDefined
  assertFileExists
  assertNumArgs
  assertRegexpMatches
);
use Permabit::Constants qw($CURRENT_VERSION_FILE);
use Permabit::SystemUtils qw(
  assertScp
  assertSystem
  createPublicDirectory
  slurp
);
use Permabit::Triage::TestInfo qw(
  %CODENAME_LOOKUP
);
use Permabit::Triage::Utils::Implementation;

use base qw(Exporter);

our @EXPORT_OK = qw(
  createIssueDirectory
  getCodename
  getHostAvailGraph
  getOwnerMoveToMaint
  getTriagePerson
);

# This is a necessary use of FindBin to get the correct per-tree behavior.
my $VERSION_FILE = "$FindBin::Bin/../../../$CURRENT_VERSION_FILE";
umask(0);

# Log4perl Logging object
my $log = Log::Log4perl->get_logger(__PACKAGE__);

# Environment-specific implementation.
our $IMPLEMENTATION;

############################################################################
# Return the instance which provides the Configured controlled functionality.
#
# @return the Configured functional instance
##
sub _getImplementation {
  if (!defined($IMPLEMENTATION)) {
    $IMPLEMENTATION = Permabit::Triage::Utils::Implementation->new();
  }

  return $IMPLEMENTATION;
}

######################################################################
# Create a directory to store logs for this issue
#
# @param issue       The issue number to use
##
sub createIssueDirectory {
  my ($issue) = assertNumArgs(1, @_);
  createPublicDirectory("/permabit/RT/$issue");
}

######################################################################
# Get a graph of rsvp machine availability using migrator logs
#
# @param startDate       The date to start graphing (yyyy-mm-dd)
# @param stopDate        The date to stop graphing (yyyy-mm-dd)
# @param classes         An array ref of rsvp classes we're interested in
#
# @return the path to the png graph file
##
sub getHostAvailGraph {
  my ($startDate, $stopDate, $classes) = assertNumArgs(3, @_);
  my $data = {};
  $data->{startDate} = $startDate;
  $data->{classes}   = $classes;
  # graph through to the end of stopDate
  $data->{endDate} = addDeltaDays($stopDate, 1);
  my $maxLogs = 10;
  my $tmpDir = tempdir( CLEANUP => 1 );
  my $firstLog = "$tmpDir/" . "migrator.log";
  my $remoteLogs = _getImplementation()->{graphing}->{remoteLogs};
  if (!defined($remoteLogs)) {
    confess("remote log directory not defined");
  }
  map {
    assertRegexpMatches('\d{4}-\d{2}-\d{2}', $_)
  } ($data->{startDate}, $data->{endDate});
  if (!scalar(@{$classes})) {
    confess("no classes defined");
  }
  assertScp($remoteLogs, "$tmpDir/");
  assertFileExists($firstLog);
  @{$classes} = map { uc($_) } @{$classes};
  $data = _getMigratorLogInfo($data, $firstLog);
  for (my $i = 0; $i < $maxLogs; $i++) {
    my $thisLog = $firstLog . ".$i";
    if (-f $thisLog) {
      $data = _getMigratorLogInfo($data, $thisLog);
    }
  }
  foreach my $class (@{$classes}) {
    foreach my $date (sort keys %{$data->{$class}}) {
      if ($date lt $data->{startDate} || $date gt $data->{endDate}) {
        delete($data->{$class}->{$date});
      }
    }
    my $dataFile = "$tmpDir/" . $class . ".dat";
    my $dat;
    if (! open $dat, ">", $dataFile) {
      confess("can't open $dataFile: $!");
    }
    foreach my $date (sort keys %{$data->{$class}}) {
      print $dat "$date $data->{$class}->{$date}\n";
    }
    close $dat;
  }
  my ($tmpl8, $outFile) = _getGnuplotHostAvailTemplate($data, $tmpDir);
  my $plotCmd = "gnuplot $tmpl8";
  assertSystem($plotCmd);
  assertFileExists($outFile);
  return $outFile;
}

######################################################################
# Get a gnuplot template for host availability graphing
#
# @param data       A hash ref containing graphing rules
# @param tmpDir     Our working tmp directory
#
# @return the path to the template
##
sub _getGnuplotHostAvailTemplate {
  my ($data, $tmpDir) = assertNumArgs(2, @_);
  my $tFH;
  my $templateFile = "$tmpDir/migrator.template";
  my $gnuplotOutputDir = _getImplementation()->{graphing}->{gnuplotOutputDir};
  if (!defined($gnuplotOutputDir)) {
    confess("gnuplot output directory not defined");
  }
  my $outFile = $gnuplotOutputDir . "/"
                . "$data->{startDate}-through-$data->{endDate}.png";
  if (! open $tFH, ">", $templateFile) {
    confess("couldn't open $templateFile: $!");
  }
  print $tFH <<END;
set terminal png size 1500, 400
set ylabel "free machines"
set yrange [0:100]
set xdata time
set format x "%m/%d %H:%M"
set timefmt "%Y-%m-%d-%H-%M"
set xrange ['$data->{startDate}':'$data->{endDate}']
set title 'Machine availablility over time'
set output '$outFile'
set key outside right
END
  print $tFH "plot";
  my $plotLines = "";
  foreach my $class (@{$data->{classes}}) {
    $plotLines .= " \'$tmpDir/$class.dat\' using 1:2 with lines "
                . "ti \'$class\', \\\n";
  }
  $plotLines = substr($plotLines, 0, -4);
  print $tFH $plotLines;
  close $tFH;
  return $templateFile, $outFile;
}

######################################################################
# Extract machine availability data from a given migrator Log
#
# @param data            A hash ref to update
# @param thisLog         The log file to parse
#
# @return a hash ref of machine availability data
##
sub _getMigratorLogInfo {
  my ($data, $thisLog) = assertNumArgs(2, @_);
  my $basePat = '^([\d-]+) (\d{2}):(\d{2}):(\d{2}),\d+[^\d]+\d+\][^\d]+(\d+) ';
  my $doWantPat = $basePat . 'free \(\d+ min\) (\w+) hosts';
  my $maintPat = $basePat . 'farms in (maintenance)';

  my @lines = slurp($thisLog);
  foreach my $line (@lines) {
    if ($line =~ /$doWantPat/) {
      $data->{$6}->{"$1-$2-$3-$4"} = $5;
    } elsif ($line =~ /$maintPat/) {
      $data->{uc($6)}->{"$1-$2-$3-$4"} = $5;
    }
  }
  return $data;
}

######################################################################
# Notice the test owner for a machine from the rsvp msg, and move that
# machine to maintenance
#
# @param host     The host to move to maintenance
# @param error    The release error
# @param rsvp     An rsvp object
##
sub getOwnerMoveToMaint {
  my ($host, $error, $rsvp) = assertNumArgs(3, @_);
  my $assignee = getTriagePerson('Software');
  $log->info("Test owner = " . ($assignee // "(undef)")
             . ", Maintenance message = $error");
  $log->info("Moving $host into maintenance");
  $rsvp->moveToMaintenance(hosts    => [$host],
                           message  => $error,
                           assignee => $assignee->{'Generic'});
}

######################################################################
# Get the triage person responsible for a particular test suite.
#
# @param component  Unused
#
# @return triage person
##
sub getTriagePerson {
  my ($component) = assertNumArgs(1, @_);

  # There is no useful value in this context.
  return undef;
}

######################################################################
# Get the codename for a given product
#
# @return codename
#
# XXX * Don't duplicate code in tagAndArchive.pl.
##
sub getCodename {
  my ($product) = assertNumArgs(1, @_);

  my $codenameLabel = "PROJECT_CODENAME";
  if ($product ne "") {
    $codenameLabel = $CODENAME_LOOKUP{$product};
  }
  my $codename;
  # Only get it if we're in a tree (and have a CURRENT_VERSION file).
  # Otherwise there's no context to say which codename it is.
  if (-e $VERSION_FILE) {
    foreach my $line (slurp($VERSION_FILE)) {
      if ($line =~ /^${codenameLabel}\s*=\s*\"?([\w\s\-\.]+\w)\"?\s*$/) {
        $codename = $1;
        last;
      }
    }
    if (!$codename) {
      $log->warn("Did not find $codenameLabel info in $VERSION_FILE");
    }
  }
  return $codename;
}

1;
