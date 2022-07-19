##
# Test the /usr/bin/sort executable
#
# $Id$
##
package testcases::Sort_t1;

use strict;
use warnings FATAL => qw(all);
use Carp qw(croak);
use English qw(-no_match_vars);
#use Fatal qw(chmod link mkdir symlink unlink);
use File::Temp qw(tmpnam);
#use Permabit::DirDiff;
use Permabit::SystemUtils qw(assertSystem);
use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

# Temporary file used by these tests
my $TMPFILE;

###############################################################################
##
sub set_up {
  my ($self) = @_;
  $self->SUPER::set_up();
  $TMPFILE = tmpnam();
}

###############################################################################
##
sub tear_down {
  my ($self) = @_;
  unlink($TMPFILE) or croak("Cannot unlink $TMPFILE");
  $self->SUPER::tear_down();
}

###############################################################################
# Test that perl and /usr/bin/sort agree on proper sort ordering.
#
# This test fails on systems where i18n stuff is installed and the user sets
# LANG or LC_ALL or LC_COLLATE to nearly anything.  In order to make sort
# agree with perl, one must use the sort command "LC_COLLATE=posix sort".
# The following modules depend upon this:  PBFSVerifier.pm
##
sub testSortOrdering {
  my ($self) = @_;
  my @TESTDATA = ('a1', 'B2', 'c3');
  my $handle;

  # Write the test data to a sorted file
  open($handle, "|LC_COLLATE=posix sort >$TMPFILE")
    or croak("Cannot open pipe to $TMPFILE:  $OS_ERROR");
  foreach my $datum (@TESTDATA) {
    print {$handle} "$datum\n"
      or croak("Cannot write to $TMPFILE:  $OS_ERROR");
  }
  close($handle) or croak("Cannot close $TMPFILE:  $OS_ERROR");

  # Read the sorted data back, and make sure that perl thinks it is in the
  # correct order
  open($handle, "<$TMPFILE")
    or croak("Cannot open $TMPFILE for reading:  $OS_ERROR");
  my $datum1 = <$handle>;
  while (my $datum2 = <$handle>) {
    $self->assert($datum1 le $datum2,
                  "sort thinks $datum1 le $datum2, but perl disagrees");
    $datum1 = $datum2;
  }
  close($handle) or croak("Cannot close $TMPFILE:  $OS_ERROR");
}

1;
