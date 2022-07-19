##
# Assertion functions.
#
# @synopsis
#
#     use Permabit::Assertions qw(assertDefined assertNumArgs);
#
#     sub foo {
#       my ($self, $arg) = assertNumArgs(2, @_);
#       assertDefined($arg);
#     }
#
# @description
#
# C<Permabit::Assertions> provides a set of methods which assert a
# condition and confess() or croak() if that condition is not met.
#
# The code is written to assume that assertions usually pass, and to
# encourage the wide use of assertions.  We try to make the passing cases
# fast, and avoid calling too many functions unless we know that a failure
# is occurring.
#
# Generally we test whether any value is undefined, because a message
# saying it is undefined is usually the most useful failure description.
# We do it like this:
#
#     if (!defined($foo)) {
#       assertDefined($foo);
#     }
#
# We expect $foo to be defined, and therefore the inline test for the
# defined case will be fast.  If $foo is undefined, we feel free to call
# the assertDefined() method to get a good quality error message.
#
# $Id$
##
package Permabit::Assertions;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Carp qw(confess croak);

use base qw(Exporter);

our @EXPORT_OK = qw(
  assertDefined
  assertDefinedEntries
  assertEq
  assertEqualNumeric
  assertEvalErrorMatches
  assertFalse
  assertFileDoesNotExist
  assertFileExists
  assertGENumeric
  assertGTNumeric
  assertIsDir
  assertIsFile
  assertKnownKeys
  assertLENumeric
  assertLTNumeric
  assertMinArgs
  assertMinMaxArgs
  assertNENumeric
  assertNe
  assertNear
  assertNotDefined
  assertNumArgs
  assertNumDefinedArgs
  assertOptionalArgs
  assertRegexpDoesNotMatch
  assertRegexpMatches
  assertTrue
  assertType
);

our $VERSION = 1.0;

######################################################################
# Return the function name (without any package prefix) of the caller of this
# function (or one of its callers). This is expensive and should only be
# invoked when we are going to confess an error.
#
# @param frames  How far up in the stack, relative to the caller of this
#                function, to get the function name to return
#
# @return the name of the function associated with the specified stack frame
##
sub _callerName {
  my ($frames) = @_;
  # Get the fully-qualified function name from caller(), then split it on
  # "::", discarding any package and class names. split() is cheaper than a
  # raw regexp, but still worth avoiding on fast success paths.
  return (split("::", (caller($frames + 1))[3]))[-1];
}

######################################################################
# Fail an assertion, invoking confess() with the string concatenation of all
# parameters. If the first parameter is not provided, it will default to the
# message "caller failed" where "caller" is the name of the function that
# called this function.
#
# @croaks Always.
##
sub _fail {
  my $message = shift || (_callerName(1) . " failed");
  confess(join("", $message, @_));
}

######################################################################
# Make an error message for a assertion that is called with the wrong
# number of arguments.  This method should only be called when we are
# going to confess an error.
#
# @param expect  The number of expected arguments
# @param got     The actual argument list
#
# @return the error message for the wrong number of arguments
##
sub _incorrectNumberOfArguments {
  my ($expect, @got) = @_;
  return ("Incorrect number of arguments to " . _callerName(1)
          . "(), should be $expect, got " . scalar(@got));
}

######################################################################
# Verify that the value specified is defined or confess with full
# stack trace.
#
# @param        val             The value to check
# @oparam       message         An optional message
##
sub assertDefined {
  if ((scalar(@_) < 1) || (scalar(@_) > 2)) {
    confess(_incorrectNumberOfArguments("1 or 2", @_));
  }
  # It's fastest to check the value parameter without naming it.
  if (!defined($_[0])) {
    my ($val, $message) = @_;
    _fail($message, "\n");
  }
}

######################################################################
# Verify that the value specified is not defined or confess with full
# stack trace.
#
# @param        val             The value to check
# @oparam       message         An optional message
##
sub assertNotDefined {
  if ((scalar(@_) < 1) || (scalar(@_) > 2)) {
    confess(_incorrectNumberOfArguments("1 or 2", @_));
  }
  # It's fastest to check the value parameter without naming it.
  if (defined($_[0])) {
    my ($val, $message) = @_;
    _fail($message, ": expected undef, got '$val'");
  }
}

######################################################################
# Verify for a given hash that the keys specifed have defined values
# or confess.
#
# @param        hash            The hash to check
# @param        keys            The keys to examine
##
sub assertDefinedEntries {
  if (scalar(@_) != 2) {
    confess(_incorrectNumberOfArguments("2", @_));
  }
  my $hash = shift;
  if (!defined($hash)) {
    assertDefined($hash);
  }
  my $keys = shift;
  if (!defined($keys)) {
    assertDefined($keys);
  }
  if (ref($keys) ne "ARRAY") {
    assertEq("ARRAY", ref($keys));
  }
  foreach my $key (@{$keys}) {
    if (!exists($hash->{$key})) {
      confess("key $key missing");
    }
    if (!defined($hash->{$key})) {
      confess("value for $key not defined");
    }
  }
}

######################################################################
# Verify that the specified value does not match the given regular
# expression or confess with full stack trace.
#
# @param  regexp   A regexp to match
# @param  val      A string to match against
# @oparam message  An optional message
##
sub assertRegexpDoesNotMatch {
  if ((scalar(@_) < 2) || (scalar(@_) > 3)) {
    confess(_incorrectNumberOfArguments("2 or 3", @_));
  }
  my $regexp = shift;
  assertDefined($regexp);
  assertType("Regexp", $regexp);
  my $val = shift;
  assertDefined($val);
  if ($val =~ $regexp) {
    _fail(shift, ": '$val' does match /$regexp/");
  }
}

######################################################################
# Verify that the specified value matches the given regular expression
# or confess with full stack trace.
#
# @param  regexp   A regexp to match
# @param  val      A string to match against
# @oparam message  An optional message
##
sub assertRegexpMatches {
  if ((scalar(@_) < 2) || (scalar(@_) > 3)) {
    confess(_incorrectNumberOfArguments("2 or 3", @_));
  }
  my $regexp = shift;
  assertDefined($regexp);
  assertType("Regexp", $regexp);
  my $val = shift;
  assertDefined($val);
  if ($val !~ $regexp) {
    _fail(shift, ": '$val' does not match /$regexp/");
  }
}

######################################################################
# Verify that EVAL_ERROR matches a regular expression or confess with full
# stack trace
#
# @param  regexp   A regexp to match
# @oparam message  An optional message
##
sub assertEvalErrorMatches {
  if ((scalar(@_) < 1) || (scalar(@_) > 2)) {
    confess(_incorrectNumberOfArguments("1 or 2", @_));
  }
  my $regexp = shift;
  my $message = shift || "assertEvalErrorMatches failed";
  if (!defined($EVAL_ERROR)) {
    confess("$message: no error to match");
  }
  assertRegexpMatches($regexp, $EVAL_ERROR, $message);
}

######################################################################
# Verify that the specified values are eq or confess with full
# stack trace.
#
# @param        ref             The expected value
# @param        val             The value to check
# @oparam       message         An optional message
##
sub assertEq {
  if ((scalar(@_) < 2) || (scalar(@_) > 3)) {
    confess(_incorrectNumberOfArguments("2 or 3", @_));
  }
  # Optimize the common success path by directly accessing the parameters.
  if (defined($_[0]) && defined($_[1]) && ($_[0] eq $_[1])) {
    return;
  }
  my ($ref, $val, $message) = @_;
  if (!defined($ref)) {
    _fail($message, ": reference value must be defined");
  }
  if (!defined($val)) {
    _fail($message, ": value to check must be defined");
  }
  _fail($message, ": reference '$ref' ne value '$val'");
}

######################################################################
# Verify that the specified values are numerically equal or confess with
# full stack trace.
#
# @param        ref             The expected value
# @param        val             The value to check
# @oparam       message         An optional message
##
sub assertEqualNumeric {
  if ((scalar(@_) < 2) || (scalar(@_) > 3)) {
    confess(_incorrectNumberOfArguments("2 or 3", @_));
  }
  # Optimize the common success path by directly accessing the parameters.
  if (defined($_[0]) && defined($_[1]) && ($_[0] == $_[1])) {
    return;
  }
  my ($ref, $val, $message) = @_;
  if (!defined($ref)) {
    _fail($message, ": reference value must be defined");
  }
  if (!defined($val)) {
    _fail($message, ": value to check must be defined");
  }
  _fail($message, ": reference '$ref' != value '$val'");
}

######################################################################
# Verify that the 1st value is numerically less than or equal to
# the 2nd or confess with full stack trace.
#
# @param        ref             The expected value
# @param        val             The value to check
# @oparam       message         An optional message
##
sub assertLENumeric {
  if ((scalar(@_) < 2) || (scalar(@_) > 3)) {
    confess(_incorrectNumberOfArguments("2 or 3", @_));
  }
  # Optimize the common success path by directly accessing the parameters.
  if (defined($_[0]) && defined($_[1]) && ($_[0] <= $_[1])) {
    return;
  }
  my ($ref, $val, $message) = @_;
  if (!defined($ref)) {
    _fail($message, ": reference value must be defined");
  }
  if (!defined($val)) {
    _fail($message, ": value to check must be defined");
  }
  _fail($message, ": reference '$ref' > value '$val'");
}

######################################################################
# Verify that the 1st value is numerically less than the 2nd
# or confess with full stack trace.
#
# @param        ref             The expected value
# @param        val             The value to check
# @oparam       message         An optional message
##
sub assertLTNumeric {
  my ($ref, $val, $message) = assertMinMaxArgs(2, 3, @_);
  if (!defined($ref)) {
    _fail($message, ": reference value must be defined");
  }
  if (!defined($val)) {
    _fail($message, ": value to check must be defined");
  }
  if ($ref >= $val) {
    _fail($message, ": reference '$ref' !< value '$val'");
  }
}

######################################################################
# Verify that the 1st value is numerically greater than or equal to
# the 2nd or confess with full stack trace.
#
# @param        ref             The expected value
# @param        val             The value to check
# @oparam       message         An optional message
##
sub assertGENumeric {
  my ($ref, $val, $message) = assertMinMaxArgs(2, 3, @_);
  if (!defined($ref)) {
    _fail($message, ": reference value must be defined");
  }
  if (!defined($val)) {
    _fail($message, ": value to check must be defined");
  }
  if ($ref < $val) {
    _fail($message, ": reference '$ref' !>= value '$val'");
  }
}

######################################################################
# Verify that the 1st value is numerically greater than the 2nd
# or confess with full stack trace.
#
# @param        ref             The expected value
# @param        val             The value to check
# @oparam       message         An optional message
##
sub assertGTNumeric {
  my ($ref, $val, $message) = assertMinMaxArgs(2, 3, @_);
  if (!defined($ref)) {
    _fail($message, ": reference value must be defined");
  }
  if (!defined($val)) {
    _fail($message, ": value to check must be defined");
  }
  if ($ref <= $val) {
    _fail($message, ": reference '$ref' !> value '$val'");
  }
}

######################################################################
# Verify that the specified hash does not contain any unspecified keys.
#
# @param       hash           A reference to the hash to be validated.
# @param       known          A list of known keys
##
sub assertKnownKeys {
  my ($hash, @known) = assertMinArgs(1, @_);
  my %known;
  foreach my $k (@known) {
    $known{$k} = 1;
  }
  foreach my $k (keys %{$hash}) {
    if (not exists $known{$k}) {
      my @callerInfo = caller(1);
      confess("Unknown hash key $k in call to ${callerInfo[3]}()");
    }
  }
}

######################################################################
# Verify that the specified values are numerically not equal or confess
# with full stack trace.
#
# @param        ref             The expected value
# @param        val             The value to check
# @oparam       message         An optional message
##
sub assertNENumeric {
  my ($ref, $val, $message) = assertMinMaxArgs(2, 3, @_);
  if (!defined($ref)) {
    _fail($message, ": reference value must be defined");
  }
  if (!defined($val)) {
    _fail($message, ": value to check must be defined");
  }
  if ($ref == $val) {
    _fail($message, ": reference '$ref' == value '$val'");
  }
}

######################################################################
# Verify that the specified values are ne or confess with full stack
# trace.
#
# @param        ref             The expected value
# @param        val             The value to check
# @oparam       message         An optional message
##
sub assertNe {
  my ($ref, $val, $message) = assertMinMaxArgs(2, 3, @_);
  if (!defined($ref)) {
    _fail($message, ": reference value must be defined");
  }
  if (!defined($val)) {
    _fail($message, ": value to check must be defined");
  }
  if ($ref eq $val) {
    _fail($message, ": reference '$ref' eq value '$val'");
  }
}

######################################################################
# Verify that the value specified is true or confess with full
# stack trace.
#
# @param        val             The value to check
# @oparam       message         An optional message
##
sub assertTrue {
  my ($val, $message) = assertMinMaxArgs(1, 2, @_);
  if (ref($val) eq 'HASH') {
    croak("hashref passed to assertTrue, possibly object?");
  }
  if (!$val) {
    _fail($message, "\n");
  }
}

######################################################################
# Verify that the value specified is false or confess with full
# stack trace.
#
# @param        val             The value to check
# @oparam       message         An optional message
##
sub assertFalse {
  my ($val, $message) = assertMinMaxArgs(1, 2, @_);
  if ($val) {
    _fail($message, "\n");
  }
}

######################################################################
# Assert that the given object is of the given type.
#
# @param type   The expect type of the object
# @param object The object whose type should be checked (via isa).
#
# @croaks If object is not of the given type
##
sub assertType {
  if (scalar(@_) != 2) {
    confess(_incorrectNumberOfArguments("2", @_));
  }
  my $type = shift;
  my $object = shift;
  if (!defined($object)) {
    assertDefined($object);
  }
  if (!$object->isa($type)) {
    confess("Parameter " . ref($object) . " is not a $type\n");
  }
}

######################################################################
# Verify that there are exactly the given number of arguments, or
# croak.
#
# @param        expected        The expected number of parameters
# @param        arguments       @at@_, as seen by the method
#
# @return The original @at@_
#
# @croaks If the wrong number of arguments have been provided
##
sub assertNumArgs {
  my $expected = shift;
  if ($expected != scalar(@_)) {
    my @callerInfo = caller(1);
    confess("Incorrect number of args to ${callerInfo[3]}(), "
            . "expected $expected, got " . scalar(@_));
  }
  return @_;
}

######################################################################
# Verify that there are exactly the given number of arguments all
# of which are defined or confess.
#
# @param        expected        The expected number of parameters
# @param        arguments       @at@_, as seen by the method
#
# @return The original @at@_
#
# @croaks If the wrong number of arguments have been provided
##
sub assertNumDefinedArgs {
  assertNumArgs(@_);
  shift(@_);
  foreach my $arg (@_) {
    assertDefined($arg);
  }
  return @_;
}

######################################################################
# Verify that there are at least the given number of arguments, or
# croak.
#
# @oparam defaultValues  An array ref of default values for optional arguments
# @param  minimum        The minimum number of parameters
# @param  arguments      @at@_, as seen by the method
#
# @return The original @at@_
#
# @croaks If the wrong number of arguments have been provided
##
sub assertMinArgs {
  my ($defaultValues, $minimum, @rest) = _parseDefaultValues(@_);
  if (scalar(@rest) < $minimum) {
    my @callerInfo = caller(1);
    confess("Incorrect number of args to ${callerInfo[3]}(), "
            . "need at least $minimum, got " . scalar(@rest));
  }
  return _applyDefaultValues($defaultValues, $minimum, @rest);
}

######################################################################
# Verify that the number of arguments is within in an interval.
#
# @oparam defaultValues  An array ref of default values for optional arguments
# @param  minimum        The minimum number of parameters
# @param  maximum        The maximum number of parameters
# @param  arguments      @at@_, as seen by the method
#
# @return The original @at@_
#
# @croaks If the wrong number of arguments have been provided
##
sub assertMinMaxArgs {
  my ($defaultValues, $minimum, $maximum, @rest) = _parseDefaultValues(@_);
  if ((scalar(@rest) < $minimum) || (scalar(@rest) > $maximum)) {
    my @callerInfo = caller(1);
    confess("Incorrect number of args to ${callerInfo[3]}(), "
            . "should be between $minimum and $maximum, got " . scalar(@rest));
  }
  if (defined($defaultValues)) {
    my $numDefaults = scalar(@{$defaultValues});
    if ($numDefaults > ($maximum - $minimum)) {
      confess("Too many default values, "
              . "should be at most " . ($maximum - $minimum) . ", "
              . "got $numDefaults");
    }
  }
  return _applyDefaultValues($defaultValues, $minimum, @rest);
}

######################################################################
# Verify that the number of required arguments are present, and that the
# optional arguments all have the expected names.
#
# @param expected   The expected number of required parameters
# @param optional   A hashref of the optional arguments.  The key is the name
#                   of an argument, and its value is the default value for the
#                   argument.
# @param arguments  @at@_, as seen by the method
#
# @return the required parameters and the hash of optional parameters
#
# @croaks if a required argument is not present, or if an unexpected optional
#         argument is present
##
sub assertOptionalArgs {
  my $expected = shift;
  my $optional = shift;
  if ($expected > scalar(@_)) {
    my @callerInfo = caller(1);
    confess("Incorrect number of args to ${callerInfo[3]}(), "
            . "expected at least $expected, got " . scalar(@_));
  }
  my @required = splice(@_, 0, $expected);
  my %optargs = (%$optional, @_);
  if (scalar(keys(%$optional)) != scalar(keys(%optargs))) {
    # there is an unexpected optional argument
    map { delete($optargs{$_}) } keys(%$optional);
    my @unexpected = sort(keys(%optargs));
    my @callerInfo = caller(1);
    confess("Unexpected optional args to ${callerInfo[3]}(): @unexpected");
  }
  return (@required, \%optargs);
}

######################################################################
# Helper function used to handle an argument list that starts with an optional
# list-ref of default values. If that list-ref is not present, it will be
# defaulted by prepending an undef to the argument list.
#
# @param arg The first argument of the list, which may be either an
#            integer or a list-ref of default values.
#
# @return An argument list that always starts with either a list-ref
#         or an undef.
##
sub _parseDefaultValues {
  if (ref($_[0]) ne 'ARRAY') {
    unshift(@_, undef);
  }
  return @_;
}

######################################################################
# Combine provided arguments and default values to produce function
# parameters.
#
# Here are two examples when $minArgs is 2:
#
#  defaultValues:        [1]
#           args:  (a, b)
#       returned:  (a, b, 1)
#
#
#  defaultValues:        [1, 2, 3, 4]
#           args:  (a, b, c)
#       returned:  (a, b, c, 2, 3, 4)
#
# XXX this scheme doesn't behave as we would like if undefs are passed
#     as arguments. Eg:
#  defaultValues:        [1, 2, 3, 4]
#           args:  (a, b, undef)
#       returned:  (a, b, undef, 2, 3, 4)
#    or
#           args:  (a, b, undef, d)
#       returned:  (a, b, undef, d, 3, 4)
#
# @param defaultValues An arrayref of default values or undef.
# @param minArgs       The minimum number of required arguments.
# @param args          The argument list provided by 'user'.
#
# @return The combined provided arguments and default arguments.
##
sub _applyDefaultValues {
  my ($defaultValues, $minArgs, @args) = @_;
  if (!defined($defaultValues)) {
    return @args;
  }
  # How many non-required args were provided by caller?
  my $numOptArgs = scalar(@args) - $minArgs;
  my @ret = @args;

  # We'll add on any extra default args not provided
  for (my $i = $numOptArgs; $i < scalar(@{$defaultValues}); ++$i) {
    push(@ret, $defaultValues->[$i]);
  }
  return @ret;
}

######################################################################
# Verify that two values are approximately equal, or in other words, that
# the absolute value of their difference is less than a tolerance value.
#
# @param  expected   The expected value.
# @param  actual     The actual value.
# @param  tolerance  The amount by which expected and actual may differ.
#                    Should either be an absolute value or a percentage
#                    (i.e. "2%") of the expected value.
# @param  name       A description of the value being compared.
##
sub assertNear {
  my ($expected, $actual, $tolerance, $name) = assertNumArgs(4, @_);
  if ($tolerance =~ s/%$//) {
    $tolerance = $expected * ($tolerance / 100.0);
  }
  if (POSIX::abs($expected - $actual) > $tolerance) {
    croak("$name off by more than allowed tolerance: $tolerance."
          . " expected: $expected, actual: $actual");
  }
}

######################################################################
# Verify that the specified entry does not exist on the filesystem or
# confess with a full stack trace.
#
# @param        name            The entry to test
# @oparam       message         An optional message
##
sub assertFileDoesNotExist {
  my ($name, $message) = assertMinMaxArgs(1, 2, @_);
  if (-e $name) {
    _fail($message, ": '$name' exists");
  }
}

######################################################################
# Verify that the specified entry exists on the filesystem or confess
# with a full stack trace.
#
# @param        name            The entry to test
# @oparam       message         An optional message
##
sub assertFileExists {
  my ($name, $message) = assertMinMaxArgs(1, 2, @_);
  if (not -e $name) {
    _fail($message, ": '$name' does not exist");
  }
}

######################################################################
# Verify that the specified entry is a directory or confess with a
# full stack trace.
#
# @param        name            The entry to test
# @oparam       message         An optional message
##
sub assertIsDir {
  my ($name, $message) = assertMinMaxArgs(1, 2, @_);
  if (not -d $name) {
    _fail($message, ": '$name' is not a directory or does not exist");
  }
}

######################################################################
# Verify that the specified entry exists and is a file or confess
# with a full stack trace.
#
# @param        name            The entry to test
# @oparam       message         An optional message
##
sub assertIsFile {
  my ($name, $message) = assertMinMaxArgs(1, 2, @_);
  if (not -f $name) {
    _fail($message, ": '$name' is not a file or does not exist");
  }
}

1;
