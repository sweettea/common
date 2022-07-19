##
# Test Permabit::ConfiguredFactory.
#
# $Id$
##
package testcases::ConfiguredFactory_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Class::Inspector;

use Permabit::Assertions qw(
  assertEq
  assertDefined
  assertNotDefined
  assertNumArgs
  assertMinMaxArgs
  assertTrue
);
use Permabit::ConfiguredFactory;
use Permabit::Utils qw(getYamlHash);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
##
sub set_up {
  my ($self) = assertNumArgs(1, @_);
  $self->SUPER::set_up();
  $ENV{PERMABIT_PERL_CONFIG} =  Class::Inspector->filename(__PACKAGE__);
  $ENV{PERMABIT_PERL_CONFIG} =~ s/pm$/yaml/;
}

########################################################################
# Test configuration include mechanism.
##
sub testInclude {
  my ($self) = assertNumArgs(1, @_);

  # Manually generate the config we expect to see by loading the included
  # config and directly performing the modifications we expect to see.
  my $included = $ENV{PERMABIT_PERL_CONFIG};
  $included =~ s/Factory//;
  my $expected = getYamlHash($included);

  $expected->{New} = { status => 'disabled' };
  $expected->{Disabled} = { status => 'disabled' };
  $expected->{Enabled}{config}{foo} = 'bar';
  $expected->{Enabled2} = undef;
  $expected->{Replaced}{file} = '/some/file.pm';
  assertSameHashes($expected, Permabit::ConfiguredFactory::getConfiguration());
}

########################################################################
# Recursively test that two hashes are the same.
#
# @param  a        The first hash to compare
# @param  b        The second hash to compare
# @oparam keyPath  The set of keys to reach the current sub-hash
##
sub assertSameHashes {
  my ($a, $b, $keyPath) = assertMinMaxArgs(['.'], 2, 3, @_);
  my %bKeys = map { ($_, 1) } keys(%{$b});
  foreach my $key (keys(%{$a})) {
    my $newKeyPath = "${keyPath}/$key";
    assertTrue(exists($b->{$key}), "$newKeyPath missing in b");
    delete($bKeys{$key});

    my @values = ($a->{$key}, $b->{$key});
    if (!defined($values[0])) {
      assertNotDefined($values[1], "$newKeyPath not defined for a");
      next;
    }

    assertDefined($values[1], "$newKeyPath not defined for b");

    my @types = map { ref($_) } @values;
    assertTrue($types[0] eq $types[1],
               "type mismatch at $newKeyPath: $types[0] vs $types[1]");

    if ($types[0] eq 'HASH') {
      assertSameHashes(@values, $newKeyPath);
      next;
    }

    assertEq(@values,
             "value mismatch at $newKeyPath: $values[0] vs $values[1]");
  }

  my @bKeys = keys(%bKeys);
  assertTrue(scalar(@bKeys) == 0,
             "keys missing from a at $keyPath: " . join(', ', @bKeys));
}

1;

