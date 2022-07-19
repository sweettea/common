##
# Methods for manipulating CURRENT_VERSION files.
#
# @synopsis
#   use Permabit::CurrentVersionFile;
#
#   my $versionFile = Permabit::CurrentVersionFile->read(<handle>);
#   my $marketingVersion = $versionFile->get('marketingVersion', 'VDO');
#
# $Id$
##
package Permabit::CurrentVersionFile;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Permabit::Assertions qw(
  assertMinMaxArgs
  assertNumArgs
);
use Permabit::VersionNumber;

# A key-value entry from a CURRENT_VERSION file looks like:
#   <PROJECT>_<KEY> <OPERATOR> <VALUE>
# Where <OPERATOR> is some non-whitespace characters ending in '='; VALUE may
# be quoted; and the spaces in the above line can be any amount of whitespace.
my $SPACE      = q|(\s*)|;
my $PROJECT    = q|([^_\s]+)|;
my $UNDERSCORE = q|(_)|;
my $KEY        = q|(\S+)|;
my $OP         = q|(\S*=)|;
my $QUOTE      = q|([\'"]?)|;
my $VALUE      = q|([^'"\s]+)|;
my $REST       = q|(.*)|;
my $RE = qr/^${SPACE}${PROJECT}${UNDERSCORE}${KEY}${SPACE}${OP}${SPACE}${QUOTE}${VALUE}${QUOTE}${REST}$/;

# These fields assign names to each of the sub-matches in the above regex.
my @FIELDS = qw(leader project underscore key sep op sep2 q1 value q2 trailer);

use overload
  '==' => \&areSame;

######################################################################
# Create an object to represent the contents to be read from a file. The handle
# will be closed.
#
# @param  handle   The handle to read
# @oparam project  The project to operate on (may be omitted if the file only
#                  contains properties for a single project)
#
# @return A new version file object representing the contents of the file
##
sub read {
  my ($package, $handle, $project) = assertMinMaxArgs(2, 3, @_);
  my @lines = ();
  if ($project) {
    $project = uc($project);
  }

  my %properties     = ();
  my $currentProject = $project;
  while (my $line = $handle->getline()) {
    my @parsed = ($line =~ $RE);
    if (!@parsed) {
      push(@lines, $line);
      next;
    }

    $line = { map({ ($_, shift(@parsed)) } @FIELDS) };
    if (!defined($currentProject)) {
      $currentProject = $line->{project};
    } elsif ($currentProject ne $line->{project}) {
      if (!defined($project)) {
        die('CURRENT_VERSION file contains multiple projects, '
            . 'must specify one');
      }

      push(@lines, $line);
      next;
    }

    if ($line->{key} =~ /VERSION/) {
      $line->{value} = Permabit::VersionNumber->new($line->{value});
    }
    push(@lines, $line);

    $properties{$line->{key}} = $line;
  }

  $handle->close();

  return bless {
    lines      => [@lines],
    project    => $currentProject,
    properties => { %properties },
  }, $package;
}

######################################################################
# Write out a version file to a handle.
#
# @param handle  The handle to which to write
##
sub write {
  my ($self, $handle) = assertNumArgs(2, @_);
  foreach my $line (@{$self->{lines}}) {
    if (!ref($line)) {
      $handle->print($line);
      next;
    }

    $handle->print(join('', map({ $line->{$_} } @FIELDS)), "\n");
  }

  $handle->close();
}

######################################################################
# Get the project associated with this version file.
#
# @return The project
##
sub getProject {
  my ($self) = assertNumArgs(1, @_);
  return $self->{project};
}

######################################################################
# Get a value for a given key
#
# @param key  The key to get
#
# @return The value of the key in the version file
##
sub get {
  my ($self, $key) = assertNumArgs(2, @_);
  return $self->{properties}{$key}{value};
}

######################################################################
# Set the value for a given key.
#
# @param key    The key to set
# @param value  The value to set
#
# @return The value that was set
##
sub set {
  my ($self, $key, $value) = assertNumArgs(3, @_);
  return $self->{properties}{$key}{value} = $value;
}

######################################################################
# Check whether another version file is the same as this one for the current
# project.
#
# @param other     The other version file
# @param reversed  Whether the arguments have been reversed from the original
#                  call to the overloaded method
#
# @return True if the two version files have the same current project, and
#         for that project, have the same key-value pairs
##
sub areSame {
  my ($self, $other, $reversed) = assertNumArgs(3, @_);
  if ($self->{project} ne $other->{project}) {
    return 0;
  }

  my $selfProperties  = $self->{properties};
  my $otherProperties = $other->{properties};
  if (!defined($selfProperties)) {
    return !defined($otherProperties);
  }

  if (!defined($otherProperties)) {
    return 0;
  }

  my @selfKeys = keys(%{$selfProperties});
  if (scalar(@selfKeys) != scalar(keys(%{$otherProperties}))) {
    return 0;
  }

  foreach my $key (@selfKeys) {
    if ($selfProperties->{$key}{value} ne $otherProperties->{$key}{value}) {
      return 0;
    }
  }

  return 1;
}

