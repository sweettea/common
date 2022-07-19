##
# Test of RegexpHash package
##
package testcases::RegexpHash_t1;

use strict;
use warnings FATAL => qw(all);
use Carp;
use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::RegexpHash;
use Permabit::Assertions qw(assertNumArgs);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my $hi = "/hello.*/";

######################################################################
# Test the basics of desired hash-like behavior.
##
sub testHashTie {
  my ($self) = assertNumArgs(1, @_);

  my %h;
  tie %h, 'Permabit::RegexpHash';

  $h{foo} = "foo";
  $h{"/hello.*/"} = "hello to you too";

  # existence
  $self->assert(exists $h{"foo"}, "exact string match");
  $self->assert(! exists $h{"woohoo"}, "no match, existence");
  $self->assert(exists $h{"hello world"}, "pattern match");
  # values
  $self->assert($h{"foo"} eq "foo", "exact string value");
  $self->assert(! defined $h{"meatloaf"}, "no match, defined");
  $self->assert($h{"hello,world"} eq "hello to you too",
                "pattern match, value");
}

######################################################################
# Test allocating a new object of this type.
##
sub testHashCreate {
  my ($self) = assertNumArgs(1, @_);

  my $h2 = new Permabit::RegexpHash;
  $h2->{$hi} = "hello again";
  $self->assert($h2->{"helloThere"} eq "hello again",
                "pattern match, value");
}

1;
