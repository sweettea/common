##
# Test the Permabit::BindUtils module
#
# $Id$
##
package testcases::BindUtils_t1;

use strict;
use warnings FATAL => qw(all);
use English qw( -no_match_vars );
use Permabit::Assertions qw(
  assertEqualNumeric
  assertNotDefined
  assertNumArgs
);
use Permabit::BindUtils qw( getSOASerialNumber );

use base qw( Permabit::Testcase );

######################################################################
# Test getSOASerialNumber() on an empty SOA record.
##
sub testGetSOASerialNumberEmpty {
  my ($self) = assertNumArgs(1, @_);
  my @zone = (
    '@ IN SOA ns. rp. ( )',
    '123 somehost.example.com.',
  );

  my $serial = getSOASerialNumber(\@zone);
  assertNotDefined($serial);
}

######################################################################
# Test getSOASerialNumber() on an empty SOA record that's also missing
# its closing paren.
##
sub testGetSOASerialNumberEmptyMissingParen {
  my ($self) = assertNumArgs(1, @_);
  my @zone = (
    '@ IN SOA ns. rp. (',
  );

  my $serial = getSOASerialNumber(\@zone);
  assertNotDefined($serial);
}

######################################################################
# Test getSOASerialNumber() on a simple SOA record.
##
sub testGetSOASerialNumberSimple {
  my ($self) = assertNumArgs(1, @_);
  my $expectedSerial = 1970010100;
  my @zone = (
    '@ IN SOA ns. rp. (',
    "$expectedSerial",
    '111',
    '222',
    '333',
    '444',
    ')',
  );

  my $serial = getSOASerialNumber(\@zone);
  assertEqualNumeric($expectedSerial, $serial);
}

######################################################################
# Test getSOASerialNumber() on a simple SOA record with a TTL.
##
sub testGetSOASerialNumberSimpleTTL {
  my ($self) = assertNumArgs(1, @_);
  my $expectedSerial = 1970010100;
  my @zone = (
    '@ 1d IN SOA ns. rp. (',
    "$expectedSerial",
    '111',
    '222',
    '333',
    '444',
    ')',
  );

  my $serial = getSOASerialNumber(\@zone);
  assertEqualNumeric($expectedSerial, $serial);
}

######################################################################
# Test getSOASerialNumber() on a compact SOA record.
##
sub testGetSOASerialNumberCompact {
  my ($self) = assertNumArgs(1, @_);
  my $expectedSerial = 1970010100;
  my @zone = (
    "@ IN SOA ns. rp. ( $expectedSerial 111 222 333 444 )",
  );

  my $serial = getSOASerialNumber(\@zone);
  assertEqualNumeric($expectedSerial, $serial);
}

######################################################################
# Test getSOASerialNumber() on a compact SOA record with a TTL.
##
sub testGetSOASerialNumberCompactTTL {
  my ($self) = assertNumArgs(1, @_);
  my $expectedSerial = 1970010100;
  my @zone = (
    "@ 1h IN SOA ns. rp. ( $expectedSerial 111 222 333 444 )",
  );

  my $serial = getSOASerialNumber(\@zone);
  assertEqualNumeric($expectedSerial, $serial);
}

######################################################################
# Test getSOASerialNumber() on a compact SOA record with a TTL.
##
sub testGetSOASerialNumberConfusing {
  my ($self) = assertNumArgs(1, @_);
  my $expectedSerial = 1970010100;
  my @zone = (
    '@ 12h IN SOA ns. rp. ( ; 12345',
    '; 67890',
    "$expectedSerial ; 13579",
    '111 ; 90111',
    '222 ; 90222',
    '333 ; 90333',
    '444 ; 90444',
    ')',
  );

  my $serial = getSOASerialNumber(\@zone);
  assertEqualNumeric($expectedSerial, $serial);
}

1;
