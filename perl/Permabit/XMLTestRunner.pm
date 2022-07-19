##
# C<Permabit::XMLTestRunner> extends C<Test::Unit::TestRunner> to format all
# output as XML, using the same DTD as Ant's
# C<XMLJUnitResultFormatter> (circa Ant 3.7):
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
#
# $Id$
##
package Permabit::XMLTestRunner;

use strict;
use warnings FATAL => qw(all);
use Benchmark;
use English qw(-no_match_vars);

use Permabit::XMLFormatter;

use base qw(Test::Unit::TestRunner);

# Hash from testname to time taken for that test
my %times;

##########################################################################
# Create a new Permabit::XMLTestRunner object.
##
sub new {
  my $pkg = shift;
  my $self = $pkg->SUPER::new(@_);
  $self->{_formatter} = Permabit::XMLFormatter->new();
  return $self;
}

######################################################################
# Overload start_suite so we can save the suite name
##
sub start_suite {
  my $self = shift;
  $self->{_pid} = $PID;
  my ($suite) = @_;
  my $name = $suite->name();
  $name =~ s/suite extracted from //;
  $self->{_formatter}->setSuiteName($name);
  $self->SUPER::start_suite(@_);
}

######################################################################
# Overload start_test to avoid having SUPER print a '.', and to save
# the starting time for this test
##
sub start_test {
  my ($self, $test) = @_;
  $times{$test->name()} = time();
}

######################################################################
# Overload start_test to save the ending time for this test
##
sub end_test {
  my ($self, $test) = @_;
  $self->{_formatter}->setTestcaseTime($test->name(),
                                       time() - $times{$test->name()});
}

######################################################################
# Overload add_error to save the test and exception
##
sub add_error {
  my ($self, $test, $exception) = @_;
  $self->{_formatter}->addTestcaseError($test->name(), $exception);
}

######################################################################
# Overload add_failure to save the test and exception
##
sub add_failure {
  my ($self, $test, $exception) = @_;
  $self->{_formatter}->addTestcaseFailure($test->name(), $exception);
}

######################################################################
# Overload add_pass to save the test
##
sub add_pass {
  my ($self, $test) = @_;
  $self->{_formatter}->addTestcaseSuccess($test->name());
}

######################################################################
# Overload print_result so that we print output in XML.  See
# description at top of file for our DTD.
##
sub print_result {
  my ($self, $result, $start_time, $end_time) = @_;
  if ($self->{_pid} == $PID) {
    # Only do the printing if we are the same proc as the one that
    # started this suite.
    $self->{_formatter}->setSuiteTime((timediff($end_time, $start_time))->[0]);
    $self->_print($self->{_formatter}->formatResult());
  }
}

######################################################################
# Overload _print so that we can filter the "Test was not successful"
# line (otherwise that line shows up outside the normal XML entity).
##
sub _print {
    my $self = shift;
    my (@args) = @_;
    if ($args[0] =~ /Test was not successful/) {
      return;
    }
    $self->SUPER::_print(@args);
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
