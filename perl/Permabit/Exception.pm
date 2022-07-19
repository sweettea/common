##
# Exceptions that may have associated types and behaviors.
#
# A Permabit::Exception is normally thrown using die, but can also be thrown by
# croak or confess with the same effect.
#
# All Permabit::Exceptions will get one stack trace (as in the style of
# confess).  If the message already contains a stack trace, we will not append
# a second stack trace.
#
# A Permabit::Exception thrown in a Permabit::AsyncSub will be rethrown in the
# originating process when the result() method is called.
#
# A Permabit::Exception can also have an associated "type".  For example:
#
#   use Permabit::Exception qw(Type);
#   die(Permabit::Exception::Type->new("Message"));
#
# $Id$
##
package Permabit::Exception;

use strict;
use warnings FATAL => qw(all);
use Carp qw(longmess);
use English qw(-no_match_vars);
use Permabit::Assertions qw(assertMinArgs assertNumArgs);

use overload q("") => \&_as_string;
use overload "cmp" => \&_cmp;

our $VERSION = 1.0;

###############################################################################
##
sub import {
  my ($package, @symbols) = assertMinArgs(1, @_);
  foreach my $symbol (@symbols) {
    eval("package $package\::$symbol; use base qw($package);");
  }
}

###############################################################################
# Creates a C<Permabit::Exception>.
#
# @param message  The exception message.
#
# @return a new C<Permabit::Exception>
##
sub new {
  my ($invocant, $message) = assertNumArgs(2, @_);
  my $class = ref($invocant) || $invocant;
  $message //= "Exception";
  if (ref($message)) {
    return $message;
  }
  if ($message !~ m/.* at .* line \d+/) {
    $message = longmess($message);
  }
  return bless \$message, $class;
}

###############################################################################
# Overload default stringification
##
sub _as_string {
  my ($self, $other, $swapped) = assertNumArgs(3, @_);
  return $$self;
}

###############################################################################
# Overload string comparison
##
sub _cmp {
  my ($self, $other, $swapped) = assertNumArgs(3, @_);
  return $swapped ? $other cmp $$self : $$self cmp $other;
}

1;
