##
# Perl mixin class that finds test binaries that need to be accessed from
# test machines.  We make this a mixin class because it allows us to avoid
# a reference cycle in our perl data structures.
#
# This mixin serves two primary purposes.  Firstly, it finds the correct
# binary executable to use.  Secondly, it records which binary executables
# the testcase is using, so that the cleanup code can be sure to shut them
# all down.
#
# There are two hash members used by this function.  "binaryDir" must be
# set up by the class that a BinaryFinder is mixed into.  The testcase sets
# this value and it is inherited by all the associated users of the
# BinaryFinder.  "_executables" is private to BinaryFinder and it records
# all the binaries that have been found.
#
# The intended primary user is the testcase code.  Like this:
#
#     package Permabit::Testcase;
#
#     # Use BinaryFinder as a mixin superclass
#     use base qw(Test::Unit::TestCase Permabit::BinaryFinder);
#
#     sub set_up {
#       my ($self) = assertNumArgs(1, @_);
#       # Create the binaryDir property
#       $self->{binaryDir} = makeFullPath($self->{nfsShareDir}, 'executables');
#       # Create the directory
#       mkpath($self->{binaryDir});
#       # Copy a list of shared files into NFS where other machines can access
#       # them.
#       assertSystem("rsync -a -L $files $self->{binaryDir}");
#       # Do other setup here
#     }
#
#     sub saveLogFiles {
#       my ($self, $saveDir) = assertNumArgs(2, @_);
#       # Save any binaries and shared-objects that were used in the test.
#       foreach my $command ($self->listBinaries()) {
#         my $binary = $self->findBinary($command);
#         # Save the binary here
#       }
#       # Save other files here
#     }
#
#     sub tear_down {
#       my ($self) = assertNumArgs(1, @_);
#       # Stop all binaries found by the BinaryFinder running on any test
#       # hosts.
#       foreach my $host ($self->getTestHosts()) {
#         foreach my $command ($self->listBinaries()) {
#           runCommand($host, "pkill -QUIT '\^$command\$'");
#           runCommand($host, "pkill -KILL '\^$command\$'");
#         }
#       }
#       # Do other teardown here
#     }
#
# The intended secondary users are components used by tests.  Like this:
#
#     package Permabit::GenericCommand;
#     #
#     # Use BinaryFinder as a mixin superclass
#     use base qw(Permabit::BinaryFinder);
#
#     sub new {
#       # Create the new object
#       #
#       if (!$parent->{standAlone}) {
#         # $parent is a reference to the Permabit::Testcase
#         $self->shareBinaryFinder($parent);
#       }
#     }
#
#     # When an executable is to be used
#     my $binary = $self->findBinary($name);
#
# $Id$
##
package Permabit::BinaryFinder;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Permabit::Assertions qw(assertDefined assertNumArgs assertType);
use Permabit::Utils qw(findExecutable);

#############################################################################
# Arrange for this instance of a BinaryFinder to share the binary pool with
# another BinaryFinder.
#
# @param other  Another BinaryFinder
##
sub shareBinaryFinder {
  my ($self, $other) = assertNumArgs(2, @_);
  assertType(__PACKAGE__, $other);
  $other->{_executables} //= {};
  $self->{binaryDir} = $other->{binaryDir};
  $self->{_executables} = $other->{_executables};
}

#############################################################################
# Assert that the requested binary exists.
#
# @param binary the name of the binary to look for
##
sub assertBinary {
  my ($self, $binary) = assertNumArgs(2, @_);
  findExecutable($binary, [ $self->{binaryDir} ]);
}

#############################################################################
# Clear the path of all binaries.
##
sub clearBinaries {
  my ($self) = assertNumArgs(1, @_);
  # Delete all the entries in the hash.  We may be sharing a reference to
  # the hash, so we cannot replace it with a reference to a new empty hash.
  foreach my $binary ($self->listBinaries()) {
    delete($self->{_executables}->{$binary});
  }
}

#############################################################################
# Find the requested binary to use.
#
# @param binary the name of the binary to look for
#
# @return the path to the binary
##
sub findBinary {
  my ($self, $binary) = assertNumArgs(2, @_);
  assertDefined($self->{binaryDir});
  $self->{_executables}->{$binary}
    ||= findExecutable($binary, [ $self->{binaryDir} ]);
  return $self->{_executables}->{$binary};
}

#############################################################################
# List the used binaries.
#
# @return a list of the names of the used binaries
##
sub listBinaries {
  my ($self) = assertNumArgs(1, @_);
  $self->{_executables} //= {};
  return keys(%{$self->{_executables}});
}

#############################################################################
# Set the path of a binary.
#
# @param binary         the name of the binary
# @param path           the path of the binary
##
sub setBinary {
  my ($self, $binary, $path) = assertNumArgs(3, @_);
  $self->{_executables}->{$binary} = $path;
}

1;
