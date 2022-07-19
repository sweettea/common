##
# Utility functions for use within Permabit
#
# C<Permabit::SupportUtils> provides utility methods for use elsewhere in the
# Permabit system.  It provides a functional interface to these
# methods due to their static nature.
#
# $Id$
##
package Permabit::SupportUtils;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Carp qw(carp cluck confess croak);
use Fatal qw(:void open close opendir);
use Data::Dumper;
use DBI;
use Log::Log4perl;
use Time::localtime;
use Time::Local;
use Permabit::Assertions qw(
  assertDefined
  assertMinMaxArgs
  assertNumArgs
);
use Permabit::Constants;
use Permabit::Parameterizer;

use base qw(Exporter);

our @EXPORT_OK = qw(
  convertToEpoch
  convertToFormatted
  execmySQL
);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

our $VERSION = 1.0;
my $parameters = Permabit::Parameterizer->new(__PACKAGE__);

my $SAVEOUT;
my $SAVEERR;

# The current default directory for expansion of %R
$parameters->defaultDir('/tmp');

# The file seperator
$parameters->fileSeperator('/');

###############################################################################
# Run a given SQL query and return the values of the results.
#
# @param  host    host to connect via MySQL
# @param  dbname  name of database to query
# @param  user    username to authenticate against database
# @param  pass    password of user to authenticate with
# @param  query   SQL Query that will be run
# @oparam key     key to sort by.
# @return         array-ref containing three values:
#                   error level
#                   total rows returned
#                   actual data returned
# @croaks         if no database connection is made
##
sub execmySQL {
  my ($host, $dbname, $user, $pass, $query, $key)
    = assertMinMaxArgs(5, 6, @_);

  $log->debug("Connecting to MySQL Database (" . $dbname . ")" .
    " on " . $host);
  my $dsn = 'DBI:mysql:database=' . $dbname .
    ';host=' . $host;
  my $dbh = DBI->connect($dsn, $user, $pass)
    or $log->fatal("Unable to connect to MySQL Server");

  assertDefined($dbh);

  $log->debug("Executing SQL Query: \"$query\"");
  my $sth = $dbh->prepare($query);
  my $rows = $sth->execute();

  $log->debug("Rows Returned: $rows");

  my $data;
  if ($query =~ /SELECT/) {
    if ($key) {
      $log->debug("Using hashref for data");
      $data = $sth->fetchall_hashref($key);
    } else {
      $log->debug("Using arrayref for data");
      $data = $sth->fetchall_arrayref();
    }
  }

  my $error = $DBI::err;
  $log->debug("Disconnecting from MySQL Database");
  $sth->finish();
  $dbh->disconnect();

  my %retval = (
                'Error' => $error,
                'Rows'  => $rows,
                'Data'  => $data,
               );
  return \%retval;
}

###############################################################################
# Convert Formatted date/time to Epoch time.
#
# @param @date       - Date to be converted [YYYY,MM,DD]
# @param @time       - Time to be converted [HH,MM,SS]
# @return $epochTime - Return Epoch conversion of formatted Date/Time
##
sub convertToEpoch {
  my ($time, $date) = assertNumArgs(2, @_);

  #############################################################################
  # Provides a Name to number (and back) translation for Date manipulation
  ##
  my %months = (
    'Jan' =>'01',
    'Feb' =>'02',
    'Mar' =>'03',
    'Apr' =>'04',
    'May' =>'05',
    'Jun' =>'06',
    'Jul' =>'07',
    'Aug' =>'08',
    'Sep' =>'09',
    'Oct' =>'10',
    'Nov' =>'11',
    'Dec' =>'12',
    '01'  => 'Jan',
    '02'  => 'Feb',
    '03'  => 'Mar',
    '04'  => 'Apr',
    '05'  => 'May',
    '06'  => 'Jun',
    '07'  => 'Jul',
    '08'  => 'Aug',
    '09'  => 'Sep',
    '10'  => 'Oct',
    '11'  => 'Nov',
    '12'  => 'Dec',
  );
  my $epochTime = timelocal(
                            $time->[2],
                            $time->[1],
                            $time->[0],
                            $date->[2],
                            $date->[1] - 1,
                            $date->[0]);
  $log->debug("Converted $date->[1]/$date->[2]/$date->[0] "
            . "$time->[2]:$time->[1]:$time->[0] to Epoch: $epochTime");
  return $epochTime;
}

###############################################################################
# Convert Epoch time to Formatted date/time.
#   Output format: MM/DD/YYYY HH:MM
#
# @param  epochTime - Epoch time to convert
# @oparam useSeconds - Put seconds in the formatted string
#
# @return $date    - Return formatted conversion from epochTime
##
sub convertToFormatted {
  my ($epochTime, $useSeconds) = assertMinMaxArgs([0], 1, 2, @_);

  $log->debug("Converting Tstamp: " . $epochTime);
  my $dateTime = scalar localtime($epochTime);
  $dateTime->[0] < 10 ? $dateTime->[0]
    = "0" . $dateTime->[0] : $dateTime->[0] = $dateTime->[0];
  $dateTime->[1] < 10 ? $dateTime->[1]
    = "0" . $dateTime->[1] : $dateTime->[1] = $dateTime->[1];
  $dateTime->[2] < 10 ? $dateTime->[2]
    = "0" . $dateTime->[2] : $dateTime->[2] = $dateTime->[2];
  $dateTime->[3] < 10 ? $dateTime->[3]
    = "0" . $dateTime->[3] : $dateTime->[3] = $dateTime->[3];
  $dateTime->[4] = $dateTime->[4] + 1;
  $dateTime->[4] < 10 ? $dateTime->[4] = "0" . $dateTime->[4]
                      : $dateTime->[4] = $dateTime->[4];
  $dateTime->[5] = $dateTime->[5] + 1900;
  my $date = "$dateTime->[5]/$dateTime->[4]/$dateTime->[3]"
           . " $dateTime->[2]:$dateTime->[1]";
  if ($useSeconds) {
    $date = $date . ":$dateTime->[0]";
  }
  return $date;
}

1;
