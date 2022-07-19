###############################################################################
# An instance of a generic command string.
#
# OVERVIEW
#
#  There is a lot of setup done around pretty much every command run in the
#  test infrastructure. This class encapsulates that setup and isolates it from
#  the test runner.
#
# CONSTRUCTION
#
#  Each CommandString declares the properties it requires, and these properties
#  are one of two kinds: regular properties, and "inherited" properties. These
#  are defined in %COMMANDSTRING_PROPERTIES and
#  %COMMANDSTRING_INHERITED_PROPERTIES.
#
#   new() - The base-class constructor declared here is typically sufficient
#     for most subclasses, and does not necessarily need to be redefined.  This
#     constructor integrates properties from the testcase and the additional
#     constructor arguments, with their default values in
#     %COMMANDSTRING_PROPERTIES and %COMMANDSTRING_INHERITED_PROPERTIES.
#
#  Occasionally, properties from an object other than the testcase should be
#  "inherited" by the CommandString.  If necessary, after construction,
#  addInheritedProperties() may be used to copy these properties into the
#  testcase.
#
# COMMAND RESOLUTION
#
#  Commands typically declare a "name" property, which is the base name of the
#  command encapsulated by the subclass of CommandString.  At construction
#  time, if a property called "binary" isn't found, then this name is looked
#  for using the BinaryFinder which is shared with the testcase.
#
# COMMAND CONSTRUCTION
#
#  The command is constructed via stringification, i.e. "$commandString"
#  returns the command string.  The construction of the command string is
#  delegated to 6 additional functions, which construct various pieces of the
#  command.  In order, they are:
#
#   getBaseCommand() - Typically does not need to be overridden.  This command
#     component simply changes the working directory to runDir (inherited from
#     the testcase), and sets the umask and ulimits.
#
#   getEnvironment() - Using the hash variable at $self->{env}, this sets the
#     environment variable for the command.  Subclasses may add additional
#     variables to the environment.
#
#   getWrapper() - Typically does not need to be overridden.  Add commands that
#     wrap the main command, including taskset, sudo, and timeout.
#
#   getMainCommand() - Constructs the command which will run under the
#     environment provided by the previous functions..
#
#   getArguments() - Constructs the command line arguments for the command.
#     It takes an optional array of argument specifiers to pass to
#     addSpecifiedArgument(), or it may directly invoke addSpecifiedArgument(),
#     addSimpleOption(), or addValueOption().
#
#   getRedirects() - Adds any output redirection for the command.
#
# $Id$
##
package Permabit::CommandString;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Carp;
use Log::Log4perl;

use Permabit::Assertions qw(
  assertDefined
  assertMinArgs
  assertMinMaxArgs
  assertNotDefined
  assertNumArgs
);
use Permabit::Utils qw(hashExtractor mergeToHash);

use base qw(Permabit::BinaryFinder Permabit::Propertied);

# Overload stringification to return the command string
use overload q("") => \&as_string;

# Log4perl logging object
my $log = Log::Log4perl->get_logger(__PACKAGE__);

our %COMMANDSTRING_PROPERTIES
  = (
     # The binary to use
     binary          => undef,
     # Any CPU affinity settings to impose (list)
     cpuAffinityList => undef,
     # Any CPU affinity settings to impose (mask)
     cpuAffinityMask => undef,
     # Whether to use sudo or not
     doSudo          => 0,
     # Whether to run the command as a particular user
     doUser          => undef,
     # Environmental variables to set
     env             => {},
     # Extra arguments to append to the command's argument list
     extraArgs       => undef,
     # Executable name (required by constructor)
     name            => undef,
     # If defined, a timeout to be applied to the command
     timeout         => undef,
    );

our %COMMANDSTRING_INHERITED_PROPERTIES
  = (
     # @ple Process environment hash
     environment => { },
     # Run directory of commands
     runDir      => undef,
     # The directory to put temp files in
     workDir     => undef,
    );

###############################################################################
# Instantiates a new CommandString.
#
# @param parent     The parent from which inherited properties will be culled.
#                   This can be either an AlbireoTest, or another
#                   Permabit::CommandString.
# @param arguments  Additional constructor arguments
##
sub new {
  my ($invocant, $parent, $arguments) = assertNumArgs(3, @_);
  my $class = ref($invocant) || $invocant;
  $log->debug("Creating instance of $class");
  my %inherited
    = %{$class->cloneClassHash("COMMANDSTRING_INHERITED_PROPERTIES")};
  my @inherited_keys = keys(%inherited);
  my $args = {
              %{$class->cloneClassHash("COMMANDSTRING_PROPERTIES")},
              hashExtractor(\%inherited, \@inherited_keys),
              hashExtractor($parent, \@inherited_keys),
              %$arguments,
             };
  my $self = bless($args, $class);

  if (defined($self->{environment})) {
    mergeToHash($self, env => $self->{environment});
  }

  if ($parent->isa("Permabit::BinaryFinder")) {
    $self->shareBinaryFinder($parent);
    if (!defined($self->{binary})) {
      $self->updateBinary();
    }
  }
  assertDefined($self->{binary}, "binary must be defined");

  return $self;
}

###############################################################################
# Add inherited properties from the provided hash.
#
# @param propSource  The hash from which to pull properties
##
sub addInheritedProperties {
  my ($self, $propSource) = assertNumArgs(2, @_);
  my %inherited
    = %{$self->cloneClassHash("COMMANDSTRING_INHERITED_PROPERTIES")};
  for my $k (keys(%inherited)) {
    if ($propSource->{$k}) {
      $self->{$k} = $propSource->{$k};
    }
  }
}

###############################################################################
# Return the array (if the input is an arrayref) or an array containing only the
# input (if the input is not an arrayref.
#
# @param value  The thing which may be an arrayref
#
# @return an array containing the value(s) input.
##
sub _toArray {
  my ($value) = assertNumArgs(1, @_);
  if (ref($value) ne 'ARRAY') {
    return ($value);
  }
  return @$value;
}

###############################################################################
# Add a simple option to the argument list if necessary
#
# @param  argsRef   A reference to the list of arguments
# @param  property  The property of $self to check
# @oparam flag      The command-line switch to add (defaults to "--$property")
##
sub addSimpleOption {
  my ($self, $argsRef, $property, $flag) = assertMinMaxArgs(3, 4, @_);
  if ($self->{$property}) {
    $flag //= "--$property";
    push(@$argsRef, $flag);
  }
}

###############################################################################
# Add an option with a value to the argument list, if defined. For GNU long
# style options, a '=' will be placed between the flag and the property,
# otherwise nothing will separate the flag from the property.
#
# @param  argsRef   A reference to the list of arguments
# @param  property  The property of $self to check
# @oparam flag      The command-line switch to add (defaults to "--$property")
##
sub addValueOption {
  my ($self, $argsRef, $property, $flag) = assertMinMaxArgs(3, 4, @_);
  if (defined($self->{$property})) {
    $flag //= "--$property";
    push(@$argsRef,
         $flag . (_isShortOption($flag) ? ' ' : '=') . $self->{$property});
  }
}

###############################################################################
# Update the binary path based on the name (or other factors subclasses might
# care about).
##
sub updateBinary {
  my ($self) = assertNumArgs(1, @_);
  assertDefined($self->{name}, "Command has no name!");
  $self->{binary} = $self->findBinary($self->{name});
}

###############################################################################
# Determines if the given flag is an old style short option (single -).
#
# @param flag  The command-line option to check
##
sub _isShortOption {
  my ($flag) = assertNumArgs(1, @_);
  return scalar($flag =~ /^-[^-]/); # first char is a '-', the second char can
}                                   # be anything but.

###############################################################################
# Build the start of every command.  By default this configures commands to run
# out of runDir, sets the umask to be permissive and makes sure we get core
# files no matter how big they are.  Most of our test infrastructure depends on
# this behavior.
#
# @return  A list of command string fragments; should not be empty.
##
sub getBaseCommand {
  my ($self) = assertNumArgs(1, @_);
  my @cmd = ("cd", $self->{runDir}, "&& umask 0 && ulimit -c unlimited &&");
  return @cmd;
}

###############################################################################
# Augment the environment ($self->{env}) with vars needed for this command
#
# @return  A list of command string fragments that will setup the necessary
#          environment variables
##
sub getEnvironment {
  my ($self) = assertNumArgs(1, @_);
  if (%{$self->{env}}) {
    return ("env",
            map {"$_=$self->{env}->{$_}"} (sort(keys(%{$self->{env}}))));
  }
  return ();
}

###############################################################################
# Create the command(s) that wrap the "main" command.
#
# @return  a list of wrapper commands
##
sub getWrapper {
  my ($self) = assertNumArgs(1, @_);
  my @cmd;

  if ($self->{cpuAffinityMask}) {
    assertNotDefined($self->{cpuAffinityList},
                     "cpuAffinityMask and cpuAffinityList"
                     . " may not both be defined");
    push(@cmd, "taskset", $self->{cpuAffinityMask});
  } elsif ($self->{cpuAffinityList}) {
    push(@cmd, "taskset -c", $self->{cpuAffinityList});
  }

  if ($self->{doSudo}) {
    push(@cmd, "sudo");
    if (defined($self->{doUser})) {
      push(@cmd, "-u", $self->{doUser});
    }
  }

  if (defined($self->{timeout})) {
    my $timeout = int($self->{timeout});
    if ($timeout > 0) {
      push(@cmd, "timeout", $timeout);
    }
  }

  return @cmd;
}

###############################################################################
# Create the "main" command.  The "main" command is the part of the command to
# which the wrappers are applied.
#
# @return  A command string fragment; should not be empty
##
sub getMainCommand {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{binary});
}

###############################################################################
# Add an argument to an array by interpreting an argument specifier, a string
# naming a property of the CommandString object and encoding how to convert
# the value of that property to a command-line argument.
#
# The specifer starts with the name of a property of the CommandString. It
# indicates whether the value of the property should be appended as-is (as a
# command argument would be), as a simple option flag (indicated by a '?'
# immediately following the property name), or as a value option (indicated by
# a '=' following the property name). Options will default to a long-form
# switch with the same name as the property, but any sequence of characters
# immediately following the type will be used as the switch instead.
# If the value of an as-is property is an array, it will be processed once for
# each value in the array (e.g. if foo is a as-is option, and $self->{foo} is
# [bar, baz], the argument list will contain bar and baz).
#
# The argument list will not be modified if the property is undefined.
#
# Examples:
#    command              =>       $self->{command}
#    debug?               =>       --debug
#    device=--name        =>       --name=$self{device}
#    key=-K               =>       -K $self->{key}
#    verbose?-v           =>       -v
#
# @param argsRef    A reference to the argument array to which to append
# @param specifier  The argument specifier to convert to an argument
##
sub addSpecifiedArgument {
  my ($self, $argsRef, $specifier) = assertNumArgs(3, @_);

  my ($property, $type, $switch) = ($specifier =~ /([^=?]+)([=?])?(.+)?/);
  assertDefined(defined($property),
                "argument specifier must name a property: $specifier");
  if (!defined($self->{$property})) {
    return;
  }

  if (!defined($type)) {
    push(@$argsRef, _toArray($self->{$property}));
  } elsif ($type eq "?") {
    $self->addSimpleOption($argsRef, $property, $switch);
  } else {
    $self->addValueOption($argsRef, $property, $switch);
  }
}

###############################################################################
# Build a list of arguments for the command.
#
# @oparam specifiers  Zero or more argument specifer strings to interpret to
#                     generate arguments to add to the list.
#
# @return  The list of arguments
##
sub getArguments {
  my ($self, @specifiers) = assertMinArgs(1, @_);
  my @args = ();
  map { $self->addSpecifiedArgument(\@args, $_); } @specifiers;
  push(@args, grep { defined($_) } $self->{extraArgs});
  return @args;
}

###############################################################################
# Return any output redirection for the command, as a list.
#
# @return  The list of output redirections
##
sub getRedirects {
  my ($self) = assertNumArgs(1, @_);
  return ();
}

###############################################################################
# Overloads default stringification to return the command string.
##
sub as_string {
  my ($self) = assertNumArgs(3, @_);
  return join(" ",
              $self->getBaseCommand(),
              $self->getWrapper(),
              $self->getEnvironment(),
              $self->getMainCommand(),
              $self->getArguments(),
              $self->getRedirects());
}

1;
