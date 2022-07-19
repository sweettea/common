##
# This module represents the pdoc2pod context when parsing a function
# entry.
#
# $Id$
##
package Pdoc::Function;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Permabit::Assertions qw(assertNumArgs);

######################################################################
# Create a new function of the given name in the given module.
#
# @param funcName       The name of this function
# @param module         This function's module
##
sub new {
  my ($invocant, $funcName, $module) = @_;
  my $class = ref($invocant) || $invocant;
  my $self = bless {
                    confesses   => '',
                    croaks      => '',
                    module      => $module,
                    name        => $funcName,
                    parameters  => '',
                    retVal      => '',
                    signature   => "=head2 $funcName ( ",
                    summary     => '',
                   }, $class;
  $module->addFunction($self);
  return $self;
}

######################################################################
# Add a textual description of this method.
##
sub addSummary {
  assertNumArgs(2, @_);
  my ($self, $description) = @_;
  $self->{summary} = $description;
}

######################################################################
# Add a required parameter to this function
##
sub addParameter {
  assertNumArgs(3, @_);
  my ($self, $name, $value) = @_;
  $self->{signature} .= "$name ";
  $self->{parameters} .= "=item I<$name>: $value\n\n";
}

######################################################################
# Add an optional parameter to this function
##
sub addOptionalParameter {
  assertNumArgs(3, @_);
  my ($self, $name, $value) = @_;
  $self->{signature} .= "[$name] ";
  $self->{parameters} .= "=item I<$name>: (optional) $value\n\n";
}

######################################################################
# Set the return value of this function
##
sub addReturnValue {
  assertNumArgs(2, @_);
  my ($self, $value) = @_;
  $self->{retVal} .= "=item I<Returns>:\n$value\n\n";
}

######################################################################
# Add a reference.
##
sub addSee {
  assertNumArgs(2, @_);
  my ($self, $value) = @_;
  chomp($value);
  $self->{summary} .= "See L<$value>\n\n";
}

######################################################################
# Set the conditions under which this function will call croak.
##
sub addCroak {
  my ($self, $value) = assertNumArgs(2, @_);
  $self->{croaks} .= "=item I<Croaks>:\n$value\n\n";
}

######################################################################
# Set the conditions under which this function will call confess.
##
sub addConfess {
  my ($self, $value) = assertNumArgs(2, @_);
  $self->{confesses} .= "=item I<Confesses>:\n$value\n\n";
}

######################################################################
# Mark that this function should inherit its documentation from the
# superclass.
##
sub inheritDoc {
  assertNumArgs(1, @_);
  my ($self) = @_;
  my $base = $self->{module}->getBase();
  $self->{summary} .= "See L<$base/\"$self->{name}\">\n\n";
}

######################################################################
# Generate the POD to describe this function
#
# @return A POD representation of this function
##
sub toString {
  assertNumArgs(1, @_);
  my ($self) = @_;

  # Ignore private functions
  if ($self->{name} =~ /^_/) {
    return '';
  }
  if (!$self->{summary}) {
    $self->{summary} = "No pdoc found";
  }

  my $output .= "$self->{signature})\n\n";
  $output .= "$self->{summary}\n\n";
  if ($self->{parameters} || $self->{retVal} || $self->{croaks}
      || $self->{confesses}) {
    $output .= "=over 4\n\n";
    if ($self->{parameters}) {
      $output .= "$self->{parameters}\n\n";
    }
    if ($self->{retVal}) {
      $output .= "$self->{retVal}\n\n";
    }
    if ($self->{croaks}) {
      $output .= "$self->{croaks}\n\n";
    }
    if ($self->{confesses}) {
      $output .= "$self->{confesses}\n\n";
    }
    $output .= "=back\n\n";
  }
  return $output;
}

1;
