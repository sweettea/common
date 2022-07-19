##
# Release info
# Constants defined for Permabit modules. Re-exports all constants
# from Permabit::MainConstants.
#
# @synopsis
#
#     use Permabit::Constants;
#
#     my $size = 13 * $KB;
#
# $Id$
##
package Permabit::Constants;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Permabit::MainConstants;

use base qw(Exporter);

our $VERSION = "1.1";
our @EXPORT = qw(
);

# Re-export all constants exported by Permabit::MainConstants
{
  push(@EXPORT, @Permabit::MainConstants::EXPORT);
}

# Add any project- or branch-specific constants below, listing them in @EXPORT
# above. Values from MainConstants can also be overridden, but be aware that
# the value defined here won't affect any derived values in MainConstants.

1;
