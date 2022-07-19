##
# Test the Utils module
#
# $Id$
##
package testcases::Assertions_t1;

use strict;
use warnings FATAL => qw(all);
use Carp;
use English qw(-no_match_vars);
use Permabit::Assertions qw(
  assertDefined
  assertDefinedEntries
  assertEq
  assertEqualNumeric
  assertEvalErrorMatches
  assertFileDoesNotExist
  assertFileExists
  assertGENumeric
  assertGTNumeric
  assertIsDir
  assertIsFile
  assertLENumeric
  assertLTNumeric
  assertMinArgs
  assertMinMaxArgs
  assertNENumeric
  assertNotDefined
  assertNumArgs
  assertOptionalArgs
  assertRegexpDoesNotMatch
  assertRegexpMatches
  assertType
);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
##
sub testAssertMinArgs {
  my ($self) = assertNumArgs(1, @_);
  my @args = (1, 2);
  my @parsedArgs = assertMinArgs(2, @args);
  $self->assert_deep_equals([@args], [@parsedArgs]);

  @parsedArgs = assertMinArgs([], 2, @args);
  $self->assert_deep_equals([@args], [@parsedArgs]);

  @parsedArgs = assertMinArgs(["foo"], 2, @args);
  $self->assert_deep_equals([@args, "foo"], [@parsedArgs]);

  @args = (1,2,3);
  @parsedArgs = assertMinArgs(["foo"], 2, @args);
  $self->assert_deep_equals([@args], [@parsedArgs]);

  @parsedArgs = assertMinArgs(["foo", "bar"], 2, @args);
  $self->assert_deep_equals([@args, "bar"], [@parsedArgs]);

  @args = (1, 2, 3, 4, 5);
  @parsedArgs = assertMinArgs(2, @args);
  $self->assert_deep_equals([@args], [@parsedArgs]);

  eval {
    assertMinArgs(2, (1));
  };
  assertEvalErrorMatches(qr/Incorrect number of args/);

  eval {
    assertMinArgs([], 2, (1));
  };
  assertEvalErrorMatches(qr/Incorrect number of args/);

  eval {
    assertMinArgs([2, 3], 2, (1));
  };
  assertEvalErrorMatches(qr/Incorrect number of args/);
}

######################################################################
##
sub testAssertMinMaxArgs {
  my ($self) = assertNumArgs(1, @_);
  my @args = (1, 2);
  my @parsedArgs = assertMinMaxArgs(2, 3, @args);
  $self->assert_deep_equals([@args], [@parsedArgs]);

  @parsedArgs = assertMinMaxArgs([], 2, 3, @args);
  $self->assert_deep_equals([@args], [@parsedArgs]);

  @parsedArgs = assertMinMaxArgs(["foo"], 2, 3, @args);
  $self->assert_deep_equals([@args, "foo"], [@parsedArgs]);

  @args = (1,2,3);
  @parsedArgs = assertMinMaxArgs(["foo"], 2, 3, @args);
  $self->assert_deep_equals([@args], [@parsedArgs]);

  eval {
    @parsedArgs = assertMinMaxArgs(["foo", "bar"], 2, 3, @args);
  };
  assertEvalErrorMatches(qr/Too many default values/);

  @parsedArgs = assertMinMaxArgs(["foo", "bar", "baz"], 2, 5, @args);
  $self->assert_deep_equals([@args, "bar", "baz"], [@parsedArgs]);


  eval {
    assertMinMaxArgs(2, 4, 1);
  };
  assertEvalErrorMatches(qr/Incorrect number of args/);

  eval {
    assertMinMaxArgs([], 2, 4, 1);
  };
  assertEvalErrorMatches(qr/Incorrect number of args/);

  eval {
    assertMinMaxArgs([1, 2], 2, 4, 1);
  };
  assertEvalErrorMatches(qr/Incorrect number of args/);

  eval {
    assertMinMaxArgs(2, 4, (1, 2, 3, 4, 5));
  };
  assertEvalErrorMatches(qr/Incorrect number of args/);


  eval {
    assertMinMaxArgs([], 2, 4, (1, 2, 3, 4, 5));
  };
  assertEvalErrorMatches(qr/Incorrect number of args/);

  eval {
    assertMinMaxArgs([2, 3], 2, 4, (1, 2, 3, 4, 5));
  };
  assertEvalErrorMatches(qr/Incorrect number of args/);
}

######################################################################
##
sub testAssertOptionalArgs {
  my ($self) = assertNumArgs(1, @_);

  _hasOptionalArgs(1);
  _hasOptionalArgs(2, foo => 42);
  _hasOptionalArgs(3, bar => 1066);
  _hasOptionalArgs(4, foo => 17, bar => 29);

  eval { _hasOptionalArgs(); };
  assertEvalErrorMatches(qr/Incorrect number of args to /);
  assertEvalErrorMatches(qr/_hasOptionalArgs/);

  eval { _hasOptionalArgs(6, foo => "OK", foobar => "oops"); };
  assertEvalErrorMatches(qr/Unexpected optional args to /);
  assertEvalErrorMatches(qr/: foobar at /);
  assertEvalErrorMatches(qr/_hasOptionalArgs/);

  eval { _hasOptionalArgs(7, foobar => "oops", barf => "double oops"); };
  assertEvalErrorMatches(qr/Unexpected optional args to /);
  assertEvalErrorMatches(qr/: barf foobar at /);
  assertEvalErrorMatches(qr/_hasOptionalArgs/);
}

######################################################################
##
sub _hasOptionalArgs {
  my ($needed, $args) = assertOptionalArgs(1, { foo => 1, bar => undef, }, @_);
}

######################################################################
# Test the numeric assertion functions.
##
sub testNumeric {
  my ($self) = assertNumArgs(1, @_);

  assertGENumeric(1, 0);
  assertGENumeric(1, 1);
  assertGTNumeric(1, 0);
  assertLTNumeric(0, 1);
  assertNENumeric(0, 1);

  eval {
    assertGENumeric(0, 1, "assertGENumeric");
  };
  assertEvalErrorMatches(qr/assertGENumeric/);

  eval {
    assertGTNumeric(0, 0, "assertGTNumeric");
  };
  assertEvalErrorMatches(qr/assertGTNumeric/);

  eval {
    assertLTNumeric(0, 0, "assertLTNumeric");
  };
  assertEvalErrorMatches(qr/assertLTNumeric/);

  eval {
    assertNENumeric(0, 0, "assertNENumeric");
  };
  assertEvalErrorMatches(qr/assertNENumeric/);
}

######################################################################
# Test assertFileDoesNotExist().
##
sub testAssertFileDoesNotExist {
  my ($self) = assertNumArgs(1, @_);
  assertFileDoesNotExist('...');
  eval {
    assertFileDoesNotExist('.');
    croak("assertFileDoesNotExist() didn't croak!");
  };
  assertEvalErrorMatches(qr/exists/);
}

######################################################################
# Test assertFileExists().
##
sub testAssertFileExists {
  my ($self) = assertNumArgs(1, @_);
  assertFileExists('.');
  eval {
    assertFileExists('...');
    croak("assertFileExists() didn't croak!");
  };
  assertEvalErrorMatches(qr/does not exist/);
}

######################################################################
# Test assertIsDir().
##
sub testAssertIsDir {
  my ($self) = assertNumArgs(1, @_);
  assertIsDir('.');
  eval {
    assertIsDir('/etc/hosts');
    croak("assertIsDir() didn't croak!");
  };
  assertEvalErrorMatches(qr/is not a directory/);
}

######################################################################
# Test assertIsFile().
##
sub testAssertIsFile {
  my ($self) = assertNumArgs(1, @_);
  assertIsFile('/etc/hosts');
  eval {
    assertIsFile('.');
    croak("assertIsDir() didn't croak!");
  };
  assertEvalErrorMatches(qr/is not a file/);
}

######################################################################
##
sub testAssertDefined {
  my ($self) = assertNumArgs(1, @_);

  eval { assertDefined(); };
  assertEvalErrorMatches(qr/Incorrect number of arguments to assertDefined/);

  assertDefined(1);

  eval { assertDefined(undef); };
  assertEvalErrorMatches(qr/assertDefined/);

  assertDefined(1, "oops");

  eval { assertDefined(undef, "we expect this one"); };
  assertEvalErrorMatches(qr/we expect this one/);

  eval { assertDefined(1, 2, 3); };
  assertEvalErrorMatches(qr/Incorrect number of arguments to assertDefined/);
}

######################################################################
##
sub testAssertDefinedEntries {
  my ($self) = assertNumArgs(1, @_);
  my $table = {
               D1 => 1,
               D2 => 2,
               D3 => 3,
               U1 => undef,
               U2 => undef,
              };

  eval { assertDefinedEntries($table); };
  assertEvalErrorMatches(qr/number of arguments to assertDefinedEntries/);

  assertDefinedEntries($table, []);
  assertDefinedEntries($table, [qw(D1)]);
  assertDefinedEntries($table, [qw(D1 D2)]);
  assertDefinedEntries($table, [qw(D1 D2 D3)]);

  eval { assertDefinedEntries($table, [qw(U1)]); };
  assertEvalErrorMatches(qr/value for U1 not defined/);

  eval { assertDefinedEntries($table, [qw(U1 U2)]); };
  assertEvalErrorMatches(qr/value for U1 not defined/);

  eval { assertDefinedEntries($table, [qw(D1 D2 D3 U1 U2)]); };
  assertEvalErrorMatches(qr/value for U1 not defined/);

  eval { assertDefinedEntries($table, [qw(M1)]); };
  assertEvalErrorMatches(qr/key M1 missing/);

  eval { assertDefinedEntries($table, [qw(M1)]); };
  assertEvalErrorMatches(qr/key M1 missing/);

  eval { assertDefinedEntries($table, [], 3); };
  assertEvalErrorMatches(qr/number of arguments to assertDefinedEntries/);
}

######################################################################
##
sub testAssertEq {
  my ($self) = assertNumArgs(1, @_);

  eval { assertEq(1); };
  assertEvalErrorMatches(qr/Incorrect number of arguments to assertEq/);

  assertEq("foo", "foo");

  eval { assertEq("foo", "bar"); };
  assertEvalErrorMatches(qr/reference .+ ne value/);

  eval { assertEq("foo", undef); };
  assertEvalErrorMatches(qr/value to check must be defined/);

  eval { assertEq(undef, "bar"); };
  assertEvalErrorMatches(qr/reference value must be defined/);

  assertEq("foo", "foo", "foo");

  eval { assertEq("foo", "bar", "foobar"); };
  assertEvalErrorMatches(qr/reference .+ ne value/);

  eval { assertEq("foo", undef, "second not defined"); };
  assertEvalErrorMatches(qr/value to check must be defined/);
  assertEvalErrorMatches(qr/second not defined/);

  eval { assertEq(undef, "bar", "first not defined"); };
  assertEvalErrorMatches(qr/reference value must be defined/);
  assertEvalErrorMatches(qr/first not defined/);

  eval { assertEq(1, 2, 3, 4); };
  assertEvalErrorMatches(qr/Incorrect number of arguments to assertEq/);
}

######################################################################
# Test assertEqualNumeric()
##
sub testEqualNumeric {
  my ($self) = assertNumArgs(1, @_);

  eval { assertEqualNumeric(1); };
  assertEvalErrorMatches(qr/number of arguments to assertEqualNumeric/);

  assertEqualNumeric(1, 1);
  assertEqualNumeric(16, 0x10);
  assertEqualNumeric(1, "1");
  assertEqualNumeric("16", "16 ");

  eval { assertEqualNumeric(1, 2); };
  assertEvalErrorMatches(qr/reference .+ != value/);

  eval { assertEqualNumeric(1, undef); };
  assertEvalErrorMatches(qr/value to check must be defined/);

  eval { assertEqualNumeric(undef, 2); };
  assertEvalErrorMatches(qr/reference value must be defined/);

  assertEqualNumeric(1, 1, "numeric");
  assertEqualNumeric(16, 0x10, "different bases");
  assertEqualNumeric(1, "1", "numeric/string");
  assertEqualNumeric("16", "16 ", "strings");

  eval { assertEqualNumeric(1, 2, "foobar"); };
  assertEvalErrorMatches(qr/reference .+ != value/);

  eval { assertEqualNumeric(1, undef, "second not defined"); };
  assertEvalErrorMatches(qr/value to check must be defined/);
  assertEvalErrorMatches(qr/second not defined/);

  eval { assertEqualNumeric(undef, 2, "first not defined"); };
  assertEvalErrorMatches(qr/reference value must be defined/);
  assertEvalErrorMatches(qr/first not defined/);

  eval { assertEqualNumeric(1, 2, 3, 4); };
  assertEvalErrorMatches(qr/number of arguments to assertEqualNumeric/);
}

######################################################################
##
sub testAssertEvalErrorMatches {
  my ($self) = assertNumArgs(1, @_);

  eval { assertEvalErrorMatches(); };
  assertEvalErrorMatches(qr/number of arguments to assertEvalErrorMatches/);

  eval {
    $EVAL_ERROR = undef;
    assertEvalErrorMatches(qr/foo/);
  };
  assertEvalErrorMatches(qr/no error to match/);

  $EVAL_ERROR = "foo";
  assertEvalErrorMatches(qr/foo/);

  eval {
    $EVAL_ERROR = "foo";
    assertEvalErrorMatches(qr/bar/);
  };
  assertEvalErrorMatches(qr/does not match/);

  eval {
    $EVAL_ERROR = undef;
    assertEvalErrorMatches(qr/foo/, "UNDEF");
  };
  assertEvalErrorMatches(qr/no error to match/);

  $EVAL_ERROR = "foo";
  assertEvalErrorMatches(qr/foo/, "MATCH");

  eval {
    $EVAL_ERROR = "foo";
    assertEvalErrorMatches(qr/bar/, "DOES NOT MATCH");
  };
  assertEvalErrorMatches(qr/does not match/);

  eval { assertEvalErrorMatches(1, 2, 3); };
  assertEvalErrorMatches(qr/number of arguments to assertEvalErrorMatches/);
}

######################################################################
# Test assertLENumeric()
##
sub testLENumeric {
  my ($self) = assertNumArgs(1, @_);

  eval { assertLENumeric(1); };
  assertEvalErrorMatches(qr/Incorrect number of arguments to assertLENumeric/);

  assertLENumeric(1, 1);
  assertLENumeric(16, 0x10);
  assertLENumeric(1, "1");
  assertLENumeric("16", "16 ");

  assertLENumeric(1, 1.5);
  assertLENumeric(1, "1.5");
  assertLENumeric("1.6", "1.6 ");

  eval { assertLENumeric(2, 1); };
  assertEvalErrorMatches(qr/reference .+ > value/);

  eval { assertLENumeric(1, undef); };
  assertEvalErrorMatches(qr/value to check must be defined/);

  eval { assertLENumeric(undef, 2); };
  assertEvalErrorMatches(qr/reference value must be defined/);

  assertLENumeric(1, 1, "numeric");
  assertLENumeric(16, 0x10, "different bases");
  assertLENumeric(1, "1", "numeric/string");
  assertLENumeric("16", "16 ", "strings");

  assertLENumeric(1, 1.5, "numeric");
  assertLENumeric(1, "1.5", "numeric/string");
  assertLENumeric("1.6", "1.6 ", "strings");

  eval { assertLENumeric(2, 1, "foobar"); };
  assertEvalErrorMatches(qr/reference .+ > value/);

  eval { assertLENumeric(1, undef, "second not defined"); };
  assertEvalErrorMatches(qr/value to check must be defined/);
  assertEvalErrorMatches(qr/second not defined/);

  eval { assertLENumeric(undef, 2, "first not defined"); };
  assertEvalErrorMatches(qr/reference value must be defined/);
  assertEvalErrorMatches(qr/first not defined/);

  eval { assertLENumeric(1, 2, 3, 4); };
  assertEvalErrorMatches(qr/Incorrect number of arguments to assertLENumeric/);
}

######################################################################
# Test assertNotDefined().
##
sub testNotDefined {
  my ($self) = assertNumArgs(1, @_);

  eval { assertNotDefined(); };
  assertEvalErrorMatches(qr/number of arguments to assertNotDefined/);

  assertNotDefined(undef);

  eval { assertNotDefined(1); };
  assertEvalErrorMatches(qr/assertNotDefined/);

  assertNotDefined(undef, "oops");

  eval { assertNotDefined(1, "we expect this one"); };
  assertEvalErrorMatches(qr/we expect this one/);

  eval { assertNotDefined(undef, undef, undef); };
  assertEvalErrorMatches(qr/number of arguments to assertNotDefined/);
}

######################################################################
# Test assertRegexpMatches().
##
sub testRegexpDoesNotMatch {
  my ($self) = assertNumArgs(1, @_);

  eval { assertRegexpDoesNotMatch(1); };
  assertEvalErrorMatches(qr/number of arguments to assertRegexpDoesNotMatch/);

  assertRegexpDoesNotMatch(qr/fo+/, "fubar");

  eval { assertRegexpDoesNotMatch(qr/fo+/, "foobar"); };
  assertEvalErrorMatches(qr/does match/);

  assertRegexpDoesNotMatch(qr/fo+/, "fubar", "a positive match");

  eval { assertRegexpDoesNotMatch(qr/fo+/, "foobar", "a negative match"); };
  assertEvalErrorMatches(qr/does match/);

  eval { assertRegexpDoesNotMatch(1, 2, 3, 4); };
  assertEvalErrorMatches(qr/number of arguments to assertRegexpDoesNotMatch/);
}

######################################################################
# Test assertRegexpMatches().
##
sub testRegexpMatches {
  my ($self) = assertNumArgs(1, @_);

  eval { assertRegexpMatches(1); };
  assertEvalErrorMatches(qr/number of arguments to assertRegexpMatches/);

  assertRegexpMatches(qr/fo+/, "foobar");

  eval { assertRegexpMatches(qr/fo*/, "baz"); };
  assertEvalErrorMatches(qr/does not match/);

  assertRegexpMatches(qr/fo+/, "foobar", "a positive match");

  eval { assertRegexpMatches(qr/fo*/, "baz", "a negative match"); };
  assertEvalErrorMatches(qr/does not match/);

  eval { assertRegexpMatches(1, 2, 3, 4); };
  assertEvalErrorMatches(qr/number of arguments to assertRegexpMatches/);
}

######################################################################
# Test assertType()
##
sub testType {
  my ($self) = assertNumArgs(1, @_);

  eval { assertType(1); };
  assertEvalErrorMatches(qr/Incorrect number of arguments to assertType/);

  assertType("Regexp", qr/foo/);

  eval { assertType("Typeless", qr/Foo/); };
  assertEvalErrorMatches(qr/is not a Typeless/);

  eval { assertType("Regexp", undef); };
  assertEvalErrorMatches(qr/assertDefined/);

  eval { assertType(1, 2, 3); };
  assertEvalErrorMatches(qr/Incorrect number of arguments to assertType/);
}

1;
