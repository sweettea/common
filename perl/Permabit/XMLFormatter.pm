# $Id$

##
# C<XMLFormatter> formats all output as XML, using the same DTD as
# Ant's C<XMLJUnitResultFormatter> (circa Ant 3.7):
#
# <XML VERSION HEADER>
# <testsuite errors="N" failures="N" name="foo" tests="N" time="N">
#   <testcase name="bar" time="N"/>
#   <testcase name="baz" time="N">
#     <failure message="blah blah blah"/>
#   </testcase>
#   <testcase name="quux" time="N">
#     <error message="blah blah blah"/>
#   </testcase>
# </testsuite>
##
package Permabit::XMLFormatter;

use strict;
use warnings FATAL => qw(all);
use Benchmark;
use English qw(-no_match_vars);
use XML::Generator;

use Permabit::Assertions qw(assertMinMaxArgs assertNumArgs);

##########################################################################
##
sub new {
  my $self = shift;
  if (!ref($self)) {
    $self = bless { }, $self;
  }
  $self->{_testTimes} = {};
  $self->{_erring} = [];
  $self->{_failing} = [];
  $self->{_passing} = [];
  return $self;
}

######################################################################
# Set the name of the currently running suite
##
sub setSuiteName {
  assertNumArgs(2, @_);
  my ($self, $suiteName) = @_;
  $self->{_suiteName} = $suiteName;
}

######################################################################
# Set the total time taken by the currently running suite
##
sub setSuiteTime {
  assertNumArgs(2, @_);
  my ($self, $suiteTime) = @_;
  $self->{_suiteTime} = $suiteTime;
}

######################################################################
# Set the time taken by the current testcase
##
sub setTestcaseTime {
  assertNumArgs(3, @_);
  my ($self, $testcase, $time) = @_;
  $self->{_testTimes}{$testcase} = $time;
}

######################################################################
# Record that a given testcase produced an error.
#
# @param testcase       The name of the erring testcase
# @param error          A textual description of the error
##
sub addTestcaseError {
  assertNumArgs(3, @_);
  my ($self, $testcase, $error) = @_;
  push(@{$self->{_erring}}, [($testcase, $error)]);
}

######################################################################
# Record that a given testcase failed.
#
# @param testcase       The name of the failing testcase
# @param failure        A textual description of the failure
##
sub addTestcaseFailure {
  assertNumArgs(3, @_);
  my ($self, $testcase, $failure) = @_;
  push(@{$self->{_failing}}, [($testcase, $failure)]);
}

######################################################################
# Record that a given testcase succeeded.
#
# @param testcase       The name of the passing testcase
##
sub addTestcaseSuccess {
  assertNumArgs(2, @_);
  my ($self, $testcase) = @_;
  push(@{$self->{_passing}}, $testcase);
}

######################################################################
# Return a fully formatted XML representation of the results of
# running this suite.
##
sub formatResult {
  assertNumArgs(1, @_);
  my ($self) = @_;
  my $testCount = (@{$self->{_erring}}) + (@{$self->{_failing}}) +
    (@{$self->{_passing}});

  # Add the headers
  my $output = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n";
  $output .= '<testsuite errors="' . (@{$self->{_erring}})
    . '" failures="' . (@{$self->{_failing}})
    . '" name="' . $self->{_suiteName}
    . '" tests="' . $testCount
    . '" time="' . $self->{_suiteTime}
    . '" >' . "\n";

  # Add all testcases
  foreach my $test (@{$self->{_passing}}) {
    $output .= $self->_formatTestCase($test);
  }
  foreach my $tuple (@{$self->{_failing}}) {
    $output .= $self->_formatTestCase($tuple->[0], 'failure', $tuple->[1]);
  }
  foreach my $tuple (@{$self->{_erring}}) {
    $output .= $self->_formatTestCase($tuple->[0], 'error', $tuple->[1]);
  }

  # done!
  $output .= '</testsuite>';
  return $output;
}

######################################################################
# Print the results of this testcase
##
sub _formatTestCase {
  my ($self, $testcase, $type, $msg)
    = assertMinMaxArgs([undef, undef], 2, 4, @_);
  my $output = "\t" . '<testcase name="' . $testcase
    . '" time="' . $self->{_testTimes}{$testcase};
  if (!$type) {
    $output .= "\" />\n";
  } else {
    $output .= "\" >\n";
    $output .= "\t\t";
    my $x = XML::Generator->new(':pretty');
    $output .= $x->$type({message => $msg});
    $output .= "\n";
    $output .= "\t</testcase>\n";
  }
  return $output;
}
 
#######################################################
# Allow a JSON dump of all static members of this object
# This non conforming function name is required by the 
# JSON library. 
##
sub TO_JSON { 
  return { %{ shift() } }; 
}

1;
