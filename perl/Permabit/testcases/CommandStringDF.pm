##
# A command for running 'df'. Intended only for testing CommandString.
#
# $Id$
##
package testcases::CommandStringDF;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Log::Log4perl;
use Permabit::Assertions qw(assertNumArgs);

use base qw(Permabit::CommandString);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

our %COMMANDSTRING_PROPERTIES
  = (
     # report as number of blocks of this size
     blockSize     => undef,
     # type of file systems to exclude
     type          => undef,
     # just print help
     help          => undef,
     # humans have ten fingers
     humanReadable => undef,
     # executable name
     name          => "df",
     # type of file systems to display
     type          => undef,
    );

our %COMMANDSTRING_INHERITED_PROPERTIES
  = (
     # Run directory of commands
     runDir => undef,
    );

######################################################################
# @inherit
##
sub getArguments {
  my ($self) = assertNumArgs(1, @_);

  # This set chosen just to be able to exercise all the specifier cases.
  my @SPECIFIERS = qw(
    blockSize=--block-size
    exclude=-x
    help?
    humanReadable?-h
    type=
    version?
    runDir
  );
  return $self->SUPER::getArguments(@SPECIFIERS);
}

1;
