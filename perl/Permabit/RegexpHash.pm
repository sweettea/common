##
# Hash with regular expression matching on keys.
#
# @synopsis
#
#    use Permabit::RegexpHash;
#
#    $versionHash = new RegexpHash;
#    $versionHash{"2.2"} = "Yes!";
#    $versionHash{"/1\..*/"} = "No, too old!";
#
#    $versionHash{"1.3"}
# => "No, too old!"
#
# @description
#
# C<Permabit::RegexpHash> provides an associative-array-like object
# which can accept regular expressions as keys when storing values,
# and during lookup will match against any stored regular expressions
# if no exact match is found.
##
package Permabit::RegexpHash;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Carp;
use Tie::Hash;

use Permabit::Assertions qw(assertNumArgs);

use base qw(Tie::StdHash);

##
# Test for existence of a matching key.
#
# @param hash       The regexp-hash.
# @param key        The key to look up.
# @return           A "found" indication, either 0 or 1.
##
sub EXISTS {
  if (exists $_[0]->{$_[1]}) {
    return 1;
  }
  foreach my $k (keys %{$_[0]}) {
    if ($k =~ m{^/(.*)/$}) {
      if ($_[1] =~ /^$1$/) {
        return 1;
      }
    }
  }
  return 0;
}

##
# Fetch a value from the hash.  If no key exactly matches the supplied
# string, try any regular-expression keys.  If more than one regular
# expression matches, the value associated with one of them will be
# returned, but it is undefined which one will be chosen.
#
# @param hash       The regexp-hash.
# @param key        The key.
# @return           The value stored with a matching key, if any.
##
sub FETCH {
  if (exists $_[0]->{$_[1]}) {
    return $_[0]->{$_[1]};
  }
  foreach my $k (keys %{$_[0]}) {
    if ($k =~ m{^/(.*)/$}) {
      if ($_[1] =~ /^$1$/) {
        return $_[0]->{$k};
      }
    }
  }
  return undef;
}

##
# Create a regexp hash.
#
# @return            The new regexp hash.
##
sub new {
  my $class = shift;
  my $self = { };
  tie %$self, $class;
  bless ($self, $class);
  return $self;
}

1;
