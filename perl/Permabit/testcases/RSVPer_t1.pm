##
# Test the Permabit::RSVPer module
#
# $Id$
##
package testcases::RSVPer_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertEq assertNumArgs assertTrue);
use Permabit::Constants;

use base qw(Permabit::Testcase);

my $log = Log::Log4perl-> get_logger(__PACKAGE__);

######################################################################
# Test recording.
##
sub testRecord {
  my ($self) = assertNumArgs(1, @_);
  my $rsvper = $self->getRSVPer();

  my $string = 'test';
  $rsvper->_record($string);
  assertEq("Call log;$string", $rsvper->{_callLog});

  $rsvper->{_callLog} = '';
  my %hash = ( 'key1' => 'value1' );
  $rsvper->_record('test', %hash);
  assertEq("Call log;${string},key1,value1", $rsvper->{_callLog});

  $rsvper->{_callLog} = '';
  $hash{'key2'} = undef;
  $rsvper->_record('test', %hash);
  # Hash entry order is not deterministic.
  assertTrue(($rsvper->{_callLog} eq "Call log;${string},key1,value1,key2,")
             || ($rsvper->{_callLog}
                 eq "Call log;${string},key2,,key1,value1"));
}

1;
