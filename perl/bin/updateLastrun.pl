#!/usr/bin/perl

##
# Updates the /permabit/build/common/lastrun symlinks.
#
# @synopsis
#
# updateLastrun.pl [--help] <source> <host> [<destination>]
#
# @description
#
# This script copies the build contained in the current tree to an
# install location (by default /permabit/builds), updates the lastrun
# symlink, and cleans up up older builds that we no longer need.
#
# @level{+}
#
# @item ARGUMENTS
#
# @level{+}
#
# @item --help
#
# Displays this message and exits.
#
# @item <source>
#
# Any location at or within the perl or tools subdirectories of the
# common source tree to be copied. The script will find the root of the
# source tree in the supplied path, so /foo/common/tools and
# /foo/common/perl/lib will all copy the same files.
#
#
# @item <host>
#
# The host on which the build is to be installed
#
# @item <destination>
#
# The root of the tree in which the build is to be installed. Defaults
# to /permabit/build/common if not specified.
#
# @level{-}
# @level{-}
#
# $Id$
##

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use FindBin;
use lib "${FindBin::RealBin}/../lib";

use Log::Log4perl qw(:easy);

use Pdoc::Generator qw(pdoc2help pdoc2usage);
use Permabit::Assertions qw(assertNumArgs);
use Permabit::LastrunUpdater;
use Permabit::SystemUtils qw(assertSystem runSystemCommand);

Log::Log4perl->easy_init({layout => '%-23d{ISO8601} %-5p %5c{1} - %m%n',
                          level  => $DEBUG,
                          file   => "STDERR"});
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use feature qw(:5.10);

my $DEFAULT_DESTINATION = '/permabit/build/common';
my $PERL_DIRECTORIES    = [map { "perl/$_" } qw(bin lib)];
my %SOURCE_DIRECTORIES  = (
  perl  => $PERL_DIRECTORIES,
  tools => 'tools/bin',
);

my $COPIERS = { map { ($_, makeCopier($_)) } keys(%SOURCE_DIRECTORIES) };

main();
exit(0);

######################################################################
# Check to ensure that the required command line argument has been
# supplied and if so write the files to /permabit/builds on the host
# and update the lastrun symlink.
##
sub main {
  my ($source, $host, $destination) = @ARGV;
  if (grep { $_ eq '--help' } @ARGV) {
    pdoc2help();
    exit(0);
  }

  if (!$source || !$host) {
    pdoc2usage();
    exit(1);
  }

  $destination //= $DEFAULT_DESTINATION;

  my $base = getBasePath($source);
  if (!$base) {
    print("No perl or tools directory in source path: $source\n");
    exit(1);
  }

  my $updater = Permabit::LastrunUpdater->new(age      => 10,
                                              baseDir  => $destination,
                                              hostname => $host,
                                              rules    => $COPIERS,
                                              source   => $base);
  $updater->runRules();
  $updater->updateLastrun();
  $updater->pruneOldDirs();
}

######################################################################
# Rsync files.
#
# @param base    The base of the tree from which to copy
# @param source  The source directory relative to the base to copy
# @param host    The destination host
# @param dir     The destination directory
# @param makeDir If true, the target subdirectory will be made, otherwise
#                the source files will copied directly into 'dir'
#
# @croaks If the rsync fails
##
sub rsyncFiles {
  my ($base, $source, $host, $dir, $makeDir) = assertNumArgs(5, @_);
  my $sourceDir = File::Spec->catdir($base, $source);
  if (!$makeDir) {
    $sourceDir .= '/';
  }
  # XXX ls calls are to debug unwritable perl/lib directories
  runSystemCommand("ls -ld $sourceDir $dir");
  assertSystem("rsync -azvL $sourceDir ${host}:$dir");
  runSystemCommand("ls -ld $sourceDir $dir");
}

######################################################################
# Copy files.
#
# @param copier The name of the copier (the key in $COPIERS)
# @param source The base of the source tree from which to copy
# @param host   The destination host
# @param dir    The destination directory
#
# @croaks If the copy fails
##
sub copyFiles {
  my ($copier, $source, $host, $dir) = assertNumArgs(4, @_);
  my $sources = $SOURCE_DIRECTORIES{$copier};
  if (ref($sources) eq 'ARRAY') {
    foreach my $sourceDir (@{$sources}) {
      rsyncFiles($source, $sourceDir, $host, $dir, 1);
    }
  } else {
    rsyncFiles($source, $sources, $host, $dir, 0);
  }
}

######################################################################
# Make a copier.
#
# @param copierName  The key in $COPIERS for this copier to use
##
sub makeCopier {
  my ($copierName) = assertNumArgs(1, @_);
  return sub { copyFiles($copierName, @_) };
}

######################################################################
# Find the path to the parent directory in a supplied path including
# the perl or tools subdirectory.
#
# @param path  The path to search
#
# @return The path to the parent directory
##
sub getBasePath {
  my ($path) = assertNumArgs(1, @_);
  my @path = File::Spec->splitdir($path);
  while (@path && ($path[-1] !~ m/^(perl|tools)$/)) {
    pop(@path);
  }

  if (@path && ($path[-1] =~ m/^(perl|tools)$/)) {
    pop(@path);
    return File::Spec->catdir(@path);
  }

  return '';
}
