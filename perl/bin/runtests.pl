#!/usr/bin/perl

##
# Script to run tests derived from Permabit::Testcase
#
# $Id$
##

use strict;
use warnings FATAL => qw(all);
use Cwd qw(abs_path cwd);
use English qw(-no_match_vars);
use FindBin;

# Setup DEFAULT_TOPDIR.  Use BEGIN because we need to compute this value
# before the following "use lib" statement is parsed.
our $DEFAULT_TOPDIR;
BEGIN {
  $DEFAULT_TOPDIR = $FindBin::RealBin;
  $DEFAULT_TOPDIR =~ s%^(.*)/(tools|perl)/.*?$%$1%;
}

# This may be invoked via a symlink.  Use the current real location of
# runtests.pl so that things don't change if the symlink gets re-pointed.
use lib "${FindBin::RealBin}/../lib";
# This may be invoked via a symlink, and we want to use libraries
# relative to the symlink, so use a path from $DEFAULT_TOPDIR.
use lib "$DEFAULT_TOPDIR/perl/lib";
use lib cwd();

use Permabit::TestRunner;

# Files which should be copied to $nfsShareDir for the tests to use.
our $SOURCE_FILES = [
  {
    files => ['perl/bin', 'perl/lib', 'perl/Permabit', 'perl/Pdoc'],
    dest  => 'src/perl',
  },
  {
    files => ['tools/bin'],
    dest  => 'src/tools',
  },
];

exit(Permabit::TestRunner::main());

1;
