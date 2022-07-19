##
# Test the Permabit::Testcase module
#
# $Id$
##
package testcases::TestcaseTest;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Log::Log4perl;
use Permabit::Assertions qw(assertEqualNumeric assertNumArgs);
use Permabit::SystemUtils qw(logCommandResults runSystemCommand);
use Test::Unit::TestSuite;

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
# @inherit
##
sub suite {
  my ($self) = shift;
  my $suite = Test::Unit::TestSuite->empty_new("TestcaseTest suite");

  # Invoke testFullName both via make_test_from_coderef and directly
  my $name = __PACKAGE__ . "::testFullNameDirectly";
  my $t = sub {
    my ($self) = shift;
    $self->fullNameTest($name);
  };
  $suite->add_test($self->make_test_from_coderef($t, $name));
  $suite->add_test(testcases::TestcaseTest->new("testFullName"));
  $suite->add_test(testcases::TestcaseTest->new("testFilterMethod"));
# Disable until we decide what to do about ALB-2016 et al.
#  $suite->add_test(testcases::TestcaseTest->new("testTimeout"));
#  $suite->add_test(testcases::TestcaseTest->new("testSetupTimeout"));
#  $suite->add_test(testcases::TestcaseTest->new("testTearDownTimeout"));
#  $suite->add_test(testcases::TestcaseTest->new("testRsvpSleepTimeout"));
#  $suite->add_test(testcases::TestcaseTest->new("testRsvpSleepNoTimeout"));

  return $suite;
}

######################################################################
##
sub fullNameTest {
  my ($self, $fullName) = assertNumArgs(2, @_);
  $self->assert_str_equals($fullName, $self->fullName());
}

######################################################################
##
sub testFullName {
  my ($self) = assertNumArgs(1, @_);
  $self->fullNameTest("testcases::TestcaseTest::testFullName");
}

######################################################################
##
sub testFilterMethod {
  my ($self) = assertNumArgs(1, @_);
  my @filters = qw(
    TimeoutDummyTest::testDummy
    testcases::TimeoutDummyTest::testDummy
  );

  my $expectPat = "DONE WITH testcases::TimeoutDummyTest::testDummy";

  my $checkSub = sub {
    my ($testMethodName, $expect) = assertNumArgs(2, @_);
    my $cmd = "./runtests.pl --copySharedFiles=0 $testMethodName";
    my $ret = runSystemCommand($cmd, 0);
    logCommandResults($ret, "TEST-OUTPUT>>>>>>", 1);
    $self->assert_matches($expect, $ret->{stderr}, "expected $expect");
  };

  # test running single tests from the command line
  map { $checkSub->($_, qr/$expectPat/) } @filters;

  # test running running multiple tests from the command line
  $checkSub->(join(" ", @filters), qr/$expectPat.*$expectPat/s);
}

######################################################################
##
sub testSetupTimeout {
  my ($self) = assertNumArgs(1, @_);
  my $cmd = "./runtests.pl --copySharedFiles=0 --setupTimeout=1 "
          . "--setupSleep=10 TimeoutDummyTest";
  my $ret = runSystemCommand($cmd, 0);
  logCommandResults($ret, "TEST-OUTPUT>>>>>>", 1);
  assertEqualNumeric(1, $ret->{status}, "test should fail");
  $self->assert_matches(qr/TIMEOUT after 1.\d+ seconds/sm,
                        $ret->{stderr}, "timeout message missing");
}

######################################################################
##
sub testTimeout {
  my ($self) = assertNumArgs(1, @_);
  my $cmd = "./runtests.pl --copySharedFiles=0 --testTimeout=1 "
          . "--testSleep=10 TimeoutDummyTest";
  my $ret = runSystemCommand($cmd, 0);
  logCommandResults($ret, "TEST-OUTPUT>>>>>>", 1);
  assertEqualNumeric(1, $ret->{status}, "test should fail");
  $self->assert_matches(qr/TIMEOUT after 1.\d+ seconds/sm,
                        $ret->{stderr}, "timeout message missing");
}

######################################################################
##
sub testRsvpSleepNoTimeout {
  my ($self) = assertNumArgs(1, @_);
  my $cmd = "./runtests.pl --copySharedFiles=0 --testTimeout=7 "
            . "--testSleep=10 --secondsRsvpSleep=5 TimeoutDummyTest";
  my $ret = runSystemCommand($cmd, 0);
  logCommandResults($ret, "TEST-OUTPUT>>>>>>", 1);
  assertEqualNumeric(0, $ret->{status}, "test should pass");
  $self->assert_matches(qr/Testcase - FINISHED/,
                        $ret->{stderr},
                        "Testcase - FINISHED message missing");
}

######################################################################
##
sub testRsvpSleepTimeout {
  my ($self) = assertNumArgs(1, @_);
  my $cmd = "./runtests.pl --copySharedFiles=0 --testTimeout=5 "
            . "--testSleep=10 --secondsRsvpSleep=2 TimeoutDummyTest";
  my $ret = runSystemCommand($cmd, 0);
  logCommandResults($ret, "TEST-OUTPUT>>>>>>", 1);
  assertEqualNumeric(1, $ret->{status}, "test should fail");
  $self->assert_matches(qr/TIMEOUT after \d+.\d+ seconds/sm,
                        $ret->{stderr}, "timeout message missing");
}

######################################################################
##
sub testTearDownTimeout {
  my ($self) = assertNumArgs(1, @_);
  my $cmd = "./runtests.pl --copySharedFiles=0 "
          . "--tearDownTimeout=1 --tearDownSleep=10 TimeoutDummyTest";
  my $ret = runSystemCommand($cmd, 0);
  logCommandResults($ret, "TEST-OUTPUT>>>>>>", 1);
  assertEqualNumeric(1, $ret->{status}, "test should fail");
  $self->assert_matches(qr/FINISHED/sm,
                        $ret->{stderr}, "main test should finish");
  $self->assert_matches(qr/CLEANUP FAILURE[^\n]*TIMEOUT after 1.\d+ seconds/sm,
                        $ret->{stderr}, "timeout message missing");
}

1;
