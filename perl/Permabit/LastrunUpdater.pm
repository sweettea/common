##
# Keeps lastrun pointers in /permabit/builds up-to-date and also deletes
# old versions.
#
# @synopsis
#
#     use Permabit::LastrunUpdater;
#
#     # %pbitBuildsDirs has been defined elsewhere but contains the
#     # rules used to copy the desired files to baseDir.
#     my $u = Permabit::LastrunUpdater->new(baseDir => '/permabit/build',
#                                           rules   => \%pbitBuildsDirs);
#     $u->runRules();
#     $u->updateLastrun();
#     $u->pruneOldDirs();
#
# @description
#
# C<Permabit::LastrunUpdater> provides a generic interface for creating
# a directory tree that contains build dirs and a lastrun pointer which
# points to the latest build and also manages cleaning up old builds
# after they've gotten old enough.
#
# $Id$
##
package Permabit::LastrunUpdater;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Carp qw(confess);
use Date::Calc qw(Delta_Days);
use File::Basename qw(basename);
use File::Spec;
use Log::Log4perl;
use Log::Log4perl::Level;
use POSIX qw(strftime);
use Permabit::Assertions qw(
  assertDefinedEntries
  assertNumArgs
  assertRegexpMatches
  assertTrue
);
use Permabit::SystemUtils qw(assertCommand runCommand);
use Storable qw(dclone);

# Log4perl Logging object
my $log = Log::Log4perl->get_logger(__PACKAGE__);

my $DATE_REGEXP = qr/^\d{4}-\d\d-\d\d-\d\d-\d\d$/;

##
# @paramList{new}
my %PROPERTIES =
  (
   # @ple How hold a directory should be before we consider it for
   # deletion (in days). Default is 7.
   age                  => 7,
   # @ple The base directory where we should start looking for
   # lastrun directories.
   baseDir              => undef,
   # @ple The minimum number of directories to keep. Even if there are
   # directories that are older than B<age> we will still keep them
   # until we have B<count> many. Default is 7.
   count                => 7,
   # @ple The hostname to create the lastrun dirs on. Default: localhost
   hostname             => 'localhost',
   # @ple The current time, of the format: %Y-%m-%d-%H-%M
   now                  => undef,
   # @ple A hashref of key, value pairs, where <key> is the subdir of
   # baseDir that contains a lastrun pointer to update and <value> is
   # a reference to a function that takes two arguments which is the
   # are: the host where the lastrun dir exists, and the path to the
   # directory that will become the new lastrun directory. It's the
   # responsibility of the function to populate the given directory
   # (on the correct host) with the necessary data. The directory passed
   # to the function will already exist on @<hostname> and will be
   # passed as an absolute path.
   rules                => undef,
   # @ple The path of the of the source directory for where the files
   # should be copied from. This will be passed to the copier function.
   source               => undef,
  );
##


######################################################################
# Instantiate a new LastrunUpdater. If B<now> was not provided, then
# the current time time will be used. B<baseDir> and B<rules> are
# required.
#
# @params{new}
##
sub new {
  my $invocant = shift(@_);
  my $class = ref($invocant) || $invocant;

  my $self = bless { %{dclone(\%PROPERTIES)}, @_ }, $class;
  $self->{now} ||= strftime("%Y-%m-%d-%H-%M", localtime());
  assertTrue(File::Spec->file_name_is_absolute($self->{baseDir}),
             "baseDir must be an abs path");
  assertRegexpMatches($DATE_REGEXP, $self->{now},
                      "'now' is not of the right format");
  assertDefinedEntries($self, [qw(baseDir rules source)]);

  # Turn down SSHMux logging b/c it's very verbose. We have to do this
  # here because if we do it in the global section, the settings will
  # get reverted when scripts configure their logger.
  Log::Log4perl->get_logger("Permabit::SSHMuxIPCSession")->level($INFO);

  return $self;
}

######################################################################
# Takes the files that were built in the tree and copy them up
# to the shared locations by running the provided B<rules>.
##
sub runRules {
  my ($self) = assertNumArgs(1, @_);
  eval {
    while (my ($subDir, $copier) = each %{$self->{rules}}) {
      my $dir = "$self->{baseDir}/$self->{now}/$subDir";
      assertCommand($self->{hostname}, "mkdir -p $dir");
      $copier->($self->{source}, $self->{hostname}, $dir);
    }
  };
  if ($EVAL_ERROR) {
    $log->warn("Evaluation error caught: $EVAL_ERROR");
    $log->warn("Aborting...");
    # Cleanup so we don't leave a half built archive.
    runCommand($self->{hostname},
               "rm -rf $self->{baseDir}/$self->{now}");
    confess($EVAL_ERROR);
  }
}

######################################################################
# Updates the lastrun link on the baseDir to point to B<now>.
##
sub updateLastrun {
  my ($self) = assertNumArgs(1, @_);
  assertCommand($self->{hostname},
                "ln -snf $self->{now} $self->{baseDir}/lastrun");
}

######################################################################
# Prunes all the subdirs in baseDir based on the following criteria:
#   1) *Always* keep at least B<count> build dirs around.
#   2) Only delete directories that are certain age.
#
# The reasoning behind having both of these criteria is that if we
# have one day with a lot of churn, we'll want to expire directories
# based on their age. Conversly, if we go a while with no builds, we
# could end up expiring all directories unless we always maintain
# a min number of old dirs.
##
sub pruneOldDirs {
  my ($self) = assertNumArgs(1, @_);
  my @dirs = $self->_getBuildDirs($self->{baseDir});
  my @maybeExpired = @dirs[$self->{count} .. $#dirs];
  my @expired = grep {$self->_isExpired(basename($_))} @maybeExpired;
  if (@expired) {
    assertCommand($self->{hostname}, "rm -r @expired");
  }
}

######################################################################
# Determines if a given time has expired. Times are considered expired
# if they are older than B<age> days from now. In its current
# implementation, only the date portion of the timestamp is used for
# the calculation.
#
# @param        existing        A prior time in Y-m-d-H-M format
#
# @return true iff the time between now and existing is > age
##
sub _isExpired {
  my ($self, $existing) = assertNumArgs(2, @_);
  my $delta = Delta_Days($self->_extractDate($existing),
                         $self->_extractDate($self->{now}));
  return $delta > $self->{age};
}

######################################################################
# Find all the build directories in a given directory. Build dirs are
# considered any dir that matches the timestamp pattern: %Y-%m-%d-%H-%M
#
# @param        dir             A base directory to search for build
#                               dirs in
#
# @return all the build-dirs or an empty list if none could be found.
##
sub _getBuildDirs {
  my ($self, $dir) = assertNumArgs(2, @_);
  my $result = assertCommand($self->{hostname}, "ls -1 $dir");
  my @dirs = map { "$dir/$_" } grep(/$DATE_REGEXP/,
                                    split(/\n/, $result->{stdout}));
  return sort {$b cmp $a} @dirs;
}

######################################################################
# Extracts just the date portion of a date-time string.
#
# @param        dateTime        %Y-%m-%d-%H-%M formated timestamp
#
# @return (year, month, day)
##
sub _extractDate {
  my ($self, $dateTime) = assertNumArgs(2, @_);
  return (split(/-/, $dateTime))[0..2];
}

1;
