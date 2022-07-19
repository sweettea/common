##
# Test Permabit::CommandString
#
# $Id$
##
package testcases::CommandString_t1;

use strict;
use warnings FATAL => qw(all);
use Carp qw(croak);
use English qw(-no_match_vars);

use Permabit::Assertions qw(
  assertEq
  assertNumArgs
);
use Permabit::CommandString;

use Permabit::testcases::CommandStringDF;

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
# @inherit
##
sub set_up {
  my ($self) = @_;
  $self->SUPER::set_up();
}

######################################################################
# @inherit
##
sub tear_down {
  my ($self) = @_;
  $self->SUPER::tear_down();
}

######################################################################
# Create a new CommandStringDF object with the specified arguments hash and
# assert that invoking getArguments() on it returns an expected string.
#
# @param $args      A hashref to pass to the command constructor
# @param $expected  The expected return value from getArguments().
##
sub _assertArguments {
  my ($self, $args, $expected) = assertNumArgs(3, @_);

  my $df = testcases::CommandStringDF->new($self, $args);
  assertEq($expected, join(" ", $df->getArguments()));
}

######################################################################
# Verify that the argument specifiers in the CommandStringDF test class work,
# which should cover all the different forms of the specifiers (flag or value
# or command; long or short style; aliased or eponymous).
##
sub testArgumentSpecifiers {
  my ($self) = assertNumArgs(1, @_);

  # Check that runDir is inherited and used as the filesystem argument.
  my $args = { };
  $self->_assertArguments($args, $self->{runDir});

  # Positional command argument is runDir, the last argument specified.
  $args->{runDir} = "/dir";
  $self->_assertArguments($args, "/dir");

  # Long eponymous flag option.
  $args->{help} = 1;
  $self->_assertArguments($args, "--help /dir");
  $args->{help} = undef;

  # Long aliased value option.
  $args->{blockSize} = 42;
  $self->_assertArguments($args, "--block-size=42 /dir");

  # Short aliased flag option.
  $args->{humanReadable} = "please";
  $self->_assertArguments($args, "--block-size=42 -h /dir");

  # Short aliased value option.
  $args->{exclude} = "nfs";
  $self->_assertArguments($args, "--block-size=42 -x nfs -h /dir");

  # Clear the map so the string doesn't get too unwieldy.
  $args = { runDir => "/dir" };

  # Long eponymous value option.
  $args->{type} = "null";
  $self->_assertArguments($args, "--type=null /dir");

  # Long eponymous flag option.
  $args->{version} = 1;
  $self->_assertArguments($args, "--type=null --version /dir");
}

1;
