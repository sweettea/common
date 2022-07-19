##
# Test the Permabit::RemoteMachine module when the output written to both
# stdout and stderr are both really large.
#
# $Id$
##
package testcases::RemoteMachine_t2;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Log::Log4perl;
use Permabit::Assertions qw(assertEq assertNumArgs);
use Permabit::AsyncSub;
use Permabit::Constants;
use Permabit::Utils qw(retryUntilTimeout);

use base qw(testcases::RemoteMachineBase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

###############################################################################
# @inherit
##
sub tear_down {
  my ($self) = assertNumArgs(1, @_);
  # This clean up has to be done here in tear_down in the case that the test
  # fails and times out.
  if (defined($self->{task})) {
    $self->{task}->kill();
    $self->{task}->wait();
  }
  $self->SUPER::tear_down();
}

###############################################################################
##
sub testBig {
  my ($self) = assertNumArgs(1, @_);

  # Run the body of the test in an AsyncSub, because the most interesting
  # failure mode is for runSystemCmd to hang.
  $self->{task} = Permabit::AsyncSub->new(code => \&_bigOutput,
                                          args => [$self]);
  $self->{task}->start();

  # We expect this to succeed and finish in about 100 seconds.
  retryUntilTimeout(sub { return $self->{task}->isComplete(); },
                    "bigOutput has hung", 10 * $MINUTE);
}

###############################################################################
# See if writing 7MB to stdout and 7MB to stderr hangs.
##
sub _bigOutput {
  my ($self) = assertNumArgs(1, @_);
  my $command = "echo foobar; echo foobar >&2";

  foreach my $index (1 .. 6) {
    $command = "for X$index in 0 1 2 3 4 5 6 7 8 9; do $command; done";
    $self->{machine}->runSystemCmd($command);
    assertEq($self->{machine}->getStdout(), $self->{machine}->getStderr());
  }
}

1;
