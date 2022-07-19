##
# Bind 9 utility functions
#
# @synopsis
#
#     use Permabit::BindUtils;
#
#     my $serial = getSOASerialNumber(\@buffer);
#
# @description
#
# C<Permabit::BindUtils> provides subroutines for extracting data
# from buffers that contain the contents of Bind 9 zone files.
#
# $Id$
##
package Permabit::BindUtils;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Permabit::Assertions qw( assertNumArgs );
use base qw(Exporter);

our @EXPORT_OK = qw (
  getSOASerialNumber
);

our $VERSION = 1.0;

######################################################################
# Extract the SOA serial number from a zone file.
#
# @param    zone    A reference to an array containing the zone file.
#
# @return           On success, the serial number; on failure, undef.
##
sub getSOASerialNumber {
  my ($zone) = assertNumArgs(1, @_);
  my $SOA =
    '^ \S+ \s+'              # domain
    . '(\d+ [a-z]? \s+)?'    # TTL (optional)
    . 'in \s+'               # class = IN
    . 'soa'                  # type = SOA
    . '(\s+ \S+){2}'         # nameserver, responsible person
    . '\s+ \('               # block open
  ;

  my $firstSOALine;
  my $i;
  my $lastSOALine;
  my $numLines;
  my $tmp;

  $numLines = scalar(@$zone);

  # Find the start of the SOA record
  $i = 0;
  while ($zone->[$i] !~ /$SOA/ix) {
    ++$i;
    if ($i == $numLines) {
      # Didn't find an SOA; return nothing
      return undef;
    }
  }
  $firstSOALine = $i;

  # Find the end of the record
  while ($i < $numLines) {
    ($tmp = $zone->[$i]) =~ s/;.*//;
    if ($tmp =~ /.* \)/x) {
      $lastSOALine = $i;
      last;
    } else {
      ++$i;
    }
  }

  if (! defined($lastSOALine)) {
    # Didn't find the end of the SOA; return nothing
    return undef;
  }

  # Search the SOA for the first integer we can find
  for ($i = $firstSOALine; $i <= $lastSOALine; $i++) {
    ($tmp = $zone->[$i]) =~ s/$SOA//ix;
    $tmp =~ s/;.*//;
    if ($tmp =~ /\s* (\d+) \D*/x) {
      return($1);
    }
  }

  # Didn't find anything; return nothing
  return undef;
}

1;
