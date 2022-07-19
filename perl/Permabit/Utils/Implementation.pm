##
# Implementation of Utils methods which may need to be over-ridden for internal
# use.
#
# @synopsis
#
#     use Permabit::Utils::Implementation;
#
#     our $IMPLEMENTATION = Permabit::Utils::Implementation->new();
#
# @description
#
# This class should only be instantiated by the Permabit::Utils
# module. Alternate implementations should derive from it and be
# Configured for instantiation.
##

package Permabit::Utils::Implementation;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Permabit::Assertions qw(assertNumArgs);
use Socket;

use base qw(Permabit::Configured);

######################################################################
# @inherit
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);
  $self->SUPER::initialize();

  # Defaults.
  $self->{chat} //= {};
  $self->{mail} //= {};
}

######################################################################
# Return the canonicalized version of this hostname, if we can find
# one.
#
# @param hostname  The hostname to canonicalize
#
# @return the canonical hostname
##
sub canonicalizeHostname {
  my ($self, $hostname) = assertNumArgs(2, @_);
  my $addr = CORE::gethostbyname($hostname);
  return ($addr
          ? (CORE::gethostbyaddr($addr, AF_INET) || $hostname)
          : $hostname);
}

######################################################################
# Consider all host names to be shortened already.
#
# @param h  The hostname to shorten
#
# @return the host name in short form
##
sub shortenHostName {
  my ($self, $h) = assertNumArgs(2, @_);

  # remove all whitespace and line breaks
  $h =~ s/\s//sg;

 return $h;
}

1;




