##
# Test Permabit::Configured.
#
# $Id$
##
package testcases::Configured_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Class::Inspector;

use Permabit::Assertions qw(
  assertEq
  assertFalse
  assertNumArgs
  assertTrue
);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
##
sub set_up {
  my ($self) = assertNumArgs(1, @_);
  $self->SUPER::set_up();
  $ENV{PERMABIT_PERL_CONFIG} =  Class::Inspector->filename(__PACKAGE__);
  $ENV{PERMABIT_PERL_CONFIG} =~ s/pm$/yaml/;
}

######################################################################
# Test that trying to load an unconfigured class fails.
##
sub testUnconfigured {
  my ($self) = assertNumArgs(1, @_);
  eval {
    Unconfigured->new();
    $self->fail("unconfigured class didn't fail");
  };

  eval {
    Unconfigure->new(foo => 1);
    $self->fail("unconfigured class with parameters didn't fail");
  };
}

######################################################################
# Test simple enabled classes.
##
sub testEnabled {
  my ($self) = assertNumArgs(1, @_);
  my $enabled = Enabled->new();
  assertTrue($enabled->{initialized});
  # With no parameters, we should get the configuration from the YAML file.
  assertEq($enabled->foo(), 'foo');

  # Check that we can override the parameters in the YAML file.
  $enabled = Enabled->new(foo => 'bar');
  assertEq($enabled->foo(), 'bar');

  # Check a class which has no config dictionary, but is marked enabled.
  $enabled = Enabled2->new();
  assertTrue($enabled->{initialized});
  # With no parameters, we should get the default initialization.
  assertEq($enabled->foo(), 'foo2');

  # Check that we can still provide configuration.
  $enabled = Enabled2->new(foo => 'bar');
  assertEq($enabled->foo(), 'bar');
}

######################################################################
# Test that an object of a disabled class can be instantiated but its methods
# will all return undef.
##
sub testDisabled {
  my ($self) = assertNumArgs(1, @_);
  my $disabled = Disabled->new();
  assertFalse($disabled->{initialized});
  assertTrue(!defined($disabled->foo()));

  $disabled = Disabled2->new();
  assertFalse($disabled->{initialized});
  assertTrue(!defined($disabled->foo()));
}

######################################################################
# Check that we can configure a different class from the one requested.
# In such a case, the configured class will be instantiated, and will have
# the correct parameters and will pass an isa test for the requested class.
#
# This could be useful when someone wants to provide an alternate
# implementation of a class. For example, we could right a Bugzilla
# class which presents the same interface as Jira.pm and the configure
# Bugzilla.pm to be the class to instantiate for Jira.pm. This allows
# new implementations to be configured without requiring any changes
# to the callers.
##
sub testReplacement {
  my ($self) = assertNumArgs(1, @_);
  $self->checkReplacement('Replaced', 1, 'foo', 'Enabled');
  $self->checkReplacement('Replaced2', 1, 'baz', 'Enabled');
  $self->checkReplacement('Replaced3', 1, 'foo2', 'Enabled2');
  $self->checkReplacement('ReplacedDisabled', 0, undef, 'Disabled');
  $self->checkReplacement('ReplacedPath', 1, 'baz:quux', 'EnabledPath');
  assertEq(Replaced->new(foo => 'quux')->foo(), 'quux');
}

######################################################################
##
sub checkReplacement {
  my ($self, $class, $initialized, $foo, $expectedClass)
    = assertNumArgs(5, @_);

  my $replaced = $class->new();
  if ($initialized) {
    assertTrue($replaced->{initialized});
  } else {
    assertFalse($replaced->{initialized});
  }

  if (defined($foo)) {
    assertEq($replaced->foo(), $foo);
  } else {
    assertTrue(!defined($replaced->foo()));
  }

  assertTrue($replaced->isa($expectedClass));
  assertFalse($replaced->isa($class));
}

1;

package Unconfigured;

use Permabit::Assertions qw(assertNumArgs);

use base qw(Permabit::Configured);

########################################################################
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);

  $self->{initialized} = 1;
}

package Enabled;

use Permabit::Assertions qw(assertNumArgs);

use base qw(Permabit::Configured);

########################################################################
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);

  $self->{initialized} = 1;
}

########################################################################
##
sub foo {
  my ($self) = assertNumArgs(1, @_);

  return $self->{foo};
}

1;

package Enabled2;

use Permabit::Assertions qw(assertNumArgs);

use base qw(Permabit::Configured);

########################################################################
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);

  $self->{initialized} = 1;
  $self->{foo} //= 'foo2';
}

########################################################################
##
sub foo {
  my ($self) = assertNumArgs(1, @_);

  return $self->{foo};
}

1;

package Disabled;

use JSON qw(encode_json);
use Permabit::Assertions qw(assertNumArgs);

use base qw(Permabit::Configured);

########################################################################
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::initialize() not replaced!");
}

########################################################################
##
sub foo {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::foo() not replaced!");
}

1;

package Disabled2;

use Permabit::Assertions qw(assertNumArgs);

use base qw(Permabit::Configured);

########################################################################
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::initialize() not replaced!");
}

########################################################################
##
sub foo {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::foo() not replaced!");
}

1;

package Replaced;

use Permabit::Assertions qw(assertNumArgs);

use base qw(Enabled);

########################################################################
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::initialize() not replaced!");
}

########################################################################
##
sub foo {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::foo() not replaced!");
}

1;

package Replaced2;

use Permabit::Assertions qw(assertNumArgs);

use base qw(Enabled);

########################################################################
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::initialize() not replaced!");
}

########################################################################
##
sub foo {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::foo() not replaced!");
}

package Replaced3;

use Permabit::Assertions qw(assertNumArgs);

use base qw(Enabled);

########################################################################
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::initialize() not replaced!");
}

########################################################################
##
sub foo {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::foo() not replaced!");
}

1;

package ReplacedDisabled;

use Permabit::Assertions qw(assertNumArgs);

use base qw(Enabled);

########################################################################
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::initialize() not replaced!");
}

########################################################################
##
sub foo {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::foo() not replaced!");
}

package ReplacedPath;

use Permabit::Assertions qw(assertNumArgs);

use base qw(Enabled);

########################################################################
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::initialize() not replaced!");
}

########################################################################
##
sub foo {
  my ($self) = assertNumArgs(1, @_);

  die(__PACKAGE__ . "::foo() not replaced!");
}

1;

