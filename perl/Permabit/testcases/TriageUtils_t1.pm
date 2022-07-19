######################################################################
# Test the Permabit::Triage::Utils module
#
# $Id$
##
package testcases::TriageUtils_t1;

use strict;
use warnings FATAL => qw(all);
use English qw( -no_match_vars );

use Permabit::Assertions qw(
  assertEvalErrorMatches
  assertGENumeric
  assertNumArgs
);
use Permabit::Triage::TestInfo qw(%TEST_INFO);
use Permabit::Triage::Utils qw(
  getCodename
  getTriagePerson
);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
##
sub testGetCodename {
  my ($self) = assertNumArgs(1, @_);
  $self->assert(getCodename(""));
}

######################################################################
##
sub testGetTriagePerson {
  my ($self) = assertNumArgs(1, @_);
  my $testInfo = \%TEST_INFO;
  my $foundTestable = 0;
  my $testInfoExceptions = 3; # the number of 'special cases' in TEST_INFO
                              #  we know won't match
  my $minMatches = scalar(keys %{$testInfo}) - $testInfoExceptions;
  foreach my $key (keys %{$testInfo}) {
    my $component;
    # looking for 2 cases:
    #  1) has a component and a prefix field = EA suite
    #  2) has a component field = Albireo suite
    #  The others are not currently/cleanly testable and have hardcoded
    #    values in Triage::Utils.
    if (($component = $testInfo->{$key}->{component} &&
          $testInfo->{$key}->{prefix}) ||
           ($component = $testInfo->{$key}->{component})) {
      my $assignee = getTriagePerson($component);
      $foundTestable++;
      $self->assert_matches(qr/\w/, $assignee,
                            "assignee not found for $component");
    }
  }
  assertGENumeric($foundTestable, $minMatches,
                  "Found only $foundTestable. Needed to find at least $minMatches");

  # Make sure it handles empty strings and undef.
  $self->assert_matches(qr/\w/, getTriagePerson(undef),
                        "assignee not found for undef");
  $self->assert_matches(qr/\w/, getTriagePerson(""),
                        "assignee not found for empty string");
}


1;
