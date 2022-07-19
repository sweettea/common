##
# Test the Permabit::ClassUtils module
#
# $Id$
##
package A;

use strict;
use warnings FATAL => qw(all);

our @ARRAY = (__PACKAGE__);
our %HASH  = ( $ARRAY[0] => __PACKAGE__,
               foo       => __PACKAGE__);

# B can clash with a Perl internal package by that name, so Z instead.
package Z;

use strict;
use warnings FATAL => qw(all);

our @ISA = qw(A);

our @ARRAY = (__PACKAGE__);
our %HASH  = ( $ARRAY[0] => __PACKAGE__,
               foo       => __PACKAGE__);

package C;

use strict;
use warnings FATAL => qw(all);

our @ISA = qw(Z);

our @ARRAY = (__PACKAGE__);
our %HASH  = ( $ARRAY[0] => __PACKAGE__,
               foo       => __PACKAGE__);

package D;

use strict;
use warnings FATAL => qw(all);

our @ISA = qw(Z C);

our @ARRAY = (__PACKAGE__);
our %HASH  = ( $ARRAY[0] => __PACKAGE__,
               foo       => __PACKAGE__);

package E;

use strict;
use warnings FATAL => qw(all);

our @ISA = qw(A Z);

our @ARRAY = (__PACKAGE__);
our %HASH  = ( $ARRAY[0] => __PACKAGE__,
               foo       => __PACKAGE__);

package testcases::ClassUtils_t1;

use strict;
use warnings FATAL => qw(all);
use Carp qw(croak);
use English qw(-no_match_vars);

use Permabit::Assertions qw(
  assertEq
  assertEqualNumeric
  assertMinArgs
  assertNumArgs
);
use Permabit::ClassUtils qw(
  getClassArray
  getClassHash
  getClassHashKeys
  getClassHierarchy
);
use Permabit::Utils qw(arraySameMembers);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
# Set up a complicated class hierarchy.
##
sub set_up {
  my ($self) = assertNumArgs(1, @_);
  $self->{objects} = { map { ($_, bless({}, $_)) } qw(A Z C D E) };
}

######################################################################
# Check the class hierarchy for a given class.
#
# @param invocant          The class or an instance of it to check
# @param expectedHierarchy The expected class hierarchy
##
sub checkClassHierarchy {
  my ($self, $invocant, @expectedHierarchy) = assertMinArgs(3, @_);
  if (!ref($invocant)) {
    $self->checkClassHierarchy($self->{objects}{$invocant},
                               @expectedHierarchy);
  }
  foreach my $package (getClassHierarchy($invocant)) {
    assertEq($package, shift(@expectedHierarchy));
  }
  assertEqualNumeric(scalar(@expectedHierarchy), 0);
}

######################################################################
# Check getClassHierarchy()
##
sub testGetClassHierarchy {
  my ($self) = assertNumArgs(1, @_);
  $self->checkClassHierarchy(qw(A A));
  $self->checkClassHierarchy(qw(Z A Z));
  $self->checkClassHierarchy(qw(C A Z C));
  $self->checkClassHierarchy(qw(D A Z C D));
  $self->checkClassHierarchy(qw(E A Z E));
}

######################################################################
# Check a composed array for a class hierarchy
#
# @param invocant       The class or an instance of it to check
# @param expectedArray  The expected array
##
sub checkClassArray {
  my ($self, $invocant, @expectedArray) = assertMinArgs(3, @_);
  if (!ref($invocant)) {
    $self->checkClassArray($self->{objects}{$invocant}, @expectedArray);
  }
  foreach my $element (@{getClassArray($invocant, 'ARRAY')}) {
    assertEq($element, shift(@expectedArray));
  }
  assertEqualNumeric(scalar(@expectedArray), 0);
}

######################################################################
# Test getClassArray()
##
sub testGetClassArray {
  my ($self) = assertNumArgs(1, @_);
  $self->checkClassArray(qw(A A));
  $self->checkClassArray(qw(Z A Z));
  $self->checkClassArray(qw(C A Z C));
  $self->checkClassArray(qw(D A Z C D));
  $self->checkClassArray(qw(E A Z E));
}

######################################################################
# Check a composed hash for a class hierarchy
#
# @param invocant      The class or an instance of it to check
# @param expectedKeys  The expected keys (although 'foo' will also be a key)
##
sub checkClassHash {
  my ($self, $invocant, @expectedKeys) = assertMinArgs(3, @_);
  my $class = ref($invocant);
  if (!$class) {
    $self->checkClassHash($self->{objects}{$invocant}, @expectedKeys);
    $class = $invocant;
  }

  my $hash = getClassHash($invocant, 'HASH');
  assertEqualNumeric(scalar(keys(%{$hash})), scalar(@expectedKeys) + 1);
  foreach my $key (@expectedKeys) {
    assertEq($key, $hash->{$key});
  }

  assertEq($class, $hash->{foo});
}

######################################################################
# Test getClassHash()
##
sub testGetClassHash {
  my ($self) = assertNumArgs(1, @_);
  $self->checkClassHash(qw(A A));
  $self->checkClassHash(qw(Z A Z));
  $self->checkClassHash(qw(C A Z C));
  $self->checkClassHash(qw(D A Z C D));
  $self->checkClassHash(qw(E A Z E));
}
