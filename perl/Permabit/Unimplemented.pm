##
# Flag method names as being unimplemented.
#
# @synopsis
#   use Permabit::Unimplemented qw(foobar)
#   # is the same as including this code:
#   # sub foobar {
#   #   Carp::confess("foobar is not implemented in " . __PACKAGE__);
#   # }
#
# $Id$
##
package Permabit::Unimplemented;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Carp;
use Permabit::Assertions qw(assertMinArgs);

sub import {
  my ($module, @symbols) = assertMinArgs(1, @_);
  my $package = (caller)[0];
  foreach my $symbol (@symbols) {
    eval <<"SYMBOL";
      package $package;
      sub $symbol {
        Carp::confess("$symbol is not implemented in $package")
      }
SYMBOL
  }
}

1;
