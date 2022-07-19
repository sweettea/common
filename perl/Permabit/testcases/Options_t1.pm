##
# Test the Options module
#
# $Id$
##
package testcases::Options_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Permabit::Options qw(
  parseARGV
  parseArray
  parseOptionsString
);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my %expected = (foo => 1,
                bar => 'baz',
                'bletch=salt' => 1,
                pepper => ["wal,do", "wee=nie", "quux"],
                xuuq => { waldo => 1,
                          wee => 'nie',
                          'quux=' => 1,
                          jack => 0,
                          'jill=f' => '',
                          qu => 'ux',
                          kufu => 'ku,fu',
                        },
                zug => 'doobie doobie do',
                zoob => '=,zoob');

my @expectedRemaining = qw(a1 a2 --a3=foo);

######################################################################
##
sub verifyResults {
  my ($self, $test, $options, @remaining) = @_;
  $self->assert_deep_equals(\%expected, $options);
  $self->assert_deep_equals(\@expectedRemaining, \@remaining);
}

my @ARGS_EXAMPLE = ('--foo',
                    '--bar=baz',
                    '--bletch\=salt',
                    'a1',
                    '--pepper=wal\,do,wee\=nie,quux',
                    '--xuuq=jack=0,jill\=f=,waldo,wee=nie,quux\=,qu=ux,kufu=ku\,fu',
                    '--zug=doobie doobie do',
                    '--zoob=\=\,zoob',
                    'a2',
                    '--',
                    '--a3=foo');

######################################################################
##
sub testParseArray {
  my ($self) = @_;
  $self->verifyResults('parseArray', parseArray(\@ARGS_EXAMPLE));
}

######################################################################
##
sub testParseString {
  my ($self) = @_;
  my $args = '--foo a1 --bar=baz --bletch\=salt --pepper=wal\,do,wee\=nie,quux --xuuq=jack=0,jill\=f=,waldo,wee=nie,quux\=,qu=ux,kufu=ku\,fu --zug="doobie doobie do" --zoob=\=\,zoob -- a2 --a3=foo';
  $self->verifyResults('parseOptionsString', parseOptionsString($args));
}

######################################################################
##
sub testParseARGV {
  my ($self) = @_;
  @ARGV = @ARGS_EXAMPLE;
  $self->verifyResults('parseARGV', &parseARGV(), @ARGV);
}

1;
