##
# Sub-class of File::Temp;
#
# @synopsis
#
#     use Permabit::Tempfile;
#     my $fh = Permabit::Tempfile->new(SUFFIX => '.foo');
#
# @description
#
# C<Permabit::Tempfile> wraps File::Temp to make sure 
# that deletes only happen in the process that created them.
#
# Since it inherits from File::Temp, it needs to use the typeglob
# mechanism used by its parent instead of the more common hashref.
#
# $Id$
##
package Permabit::Tempfile;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use File::Temp;
use Log::Log4perl;

use Permabit::Assertions qw(assertMinArgs assertNumArgs);

use base qw(File::Temp);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
# Instantiate a new temporary file
##
sub new {
  my ($invocant, @other) = assertMinArgs(1, @_);
  my $class = ref($invocant) || $invocant;
  my $self = $class->SUPER::new(@other);
  ${*$self}{pid} = $PID;
  return $self;
}

######################################################################
# The destructor
##
sub DESTROY {
  # So that errors do not leak out, Localize $EVAL_ERROR and use eval
  local $EVAL_ERROR;
  eval {
    my $self = shift;
    if (${*$self}{pid} == $PID) {
      # We count upon SUPER::DESTROY to localize the special variables that
      # it may change
      $self->SUPER::DESTROY();
    }
  };
}

1;
