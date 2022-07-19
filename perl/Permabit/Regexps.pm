##
# Release info
# Common Regexps defined for Permabit modules.
#
# @synopsis
#
#     use Permabit::Regexps;
#
#     my ($snapshot) = ($info =~ /<tag>($SNAPSHOT_DATE)</tag>
#
# $Id#
##
package Permabit::Regexps;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use base qw(Exporter);

our @EXPORT_OK = qw(
  $ISODATE_TZ
  $SNAPSHOT_NAME
);

our $ISODATE_TZ = qr/\d{4}-\d{2}-\d{2}T\d{2}\.\d{2}.\d{2}[-+]\d{4}/;
our $SNAPSHOT_NAME = $ISODATE_TZ;

1;

