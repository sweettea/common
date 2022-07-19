##
# Base class for objects which are to be configured and/or enabled via a
# config file.
#
# @synopsis
#
#     package Foo;
#
#     use base qw(Permabit::Configured);
#
#     sub initialize {
#       ...
#     }
#
# @description
#
# C<Permabit::Configured> is the base class for objects whose configuration
# is controlled by a config file.
#
#
# $Id$
##
package Permabit::Configured;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Permabit::Assertions qw(assertNumArgs);
use Permabit::ConfiguredFactory;

########################################################################
# Create a new configured object.
#
# @oparam parameters  Optional parameters which will override the factory's
#                     configuration
##
sub new {
  return Permabit::ConfiguredFactory::make(@_);
}

########################################################################
# Perform any sub-class specific initialization.
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);
}

1;
