##
# Test of AsyncSub package
#
# $Id$
##
package testcases::AsyncSubTest;

use strict;
use warnings FATAL => qw(all);
use Carp;
use English qw(-no_match_vars);
use Log::Log4perl;
use Permabit::Assertions qw(
  assertDefined
  assertEq
  assertEqualNumeric
  assertEvalErrorMatches
  assertNotDefined
  assertNumArgs
);
use Permabit::AsyncSub;

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
##
sub testQuickSub {
  my ($self) = assertNumArgs(1, @_);

  my $async = Permabit::AsyncSub->new(code => sub { return "xyzzy"; });
  assertEq("initialized", $async->status(), "pre-start status");
  $async->start();
  my $status = $async->status();
  $self->assert($status eq "pending" || $status eq "ok",
                "post-start status: $status");
  assertNotDefined($async->error(), "an error shouldn't occur");
  assertEq("ok", $async->status(), "post-wait status");
  assertEq("xyzzy", $async->result(), "correct result obtained");
}

######################################################################
##
sub testBadSub {
  my ($self) = assertNumArgs(1, @_);

  my $async = Permabit::AsyncSub->new(code => sub { die("oops"); });
  assertEq("initialized", $async->status(), "pre-start status");
  $async->start();
  my $status = $async->status();
  $self->assert($status eq "pending" || $status eq "error",
                "post-start status: $status");
  assertDefined($async->error(), "an error should have occurred");
  assertEq("error", $async->status(), "post-wait status");
  $self->assert_matches(qr/oops/, $async->error(), "error message returned");

  eval {
    $async->result();
  };
  assertEvalErrorMatches(qr/oops/, "re-raised error message");
}

######################################################################
##
sub testSleepSub {
  my ($self) = assertNumArgs(1, @_);

  my $async = Permabit::AsyncSub->new(code => sub { sleep(5); return 1; });
  assertEq("initialized", $async->status(), "pre-start status");
  $async->start();
  assertEq("pending",  $async->status(), "post-start status");
  $async->result();
  assertEq("ok", $async->status(), "post-sleep status");
  assertNotDefined($async->error(), "an error occurred");
  assertEqualNumeric(1, $async->result(), "correct result obtained");
}

######################################################################
# Verify that sending a SIGKILL to an async sub gives the correct
# return status.
##
sub testSignalKill {
  my ($self) = assertNumArgs(1, @_);

  my $async = Permabit::AsyncSub->new(code => sub {
                                        kill('KILL', $PID);
                                      });
  $async->start();
  $async->wait();
  assertEq('failure', $async->status(), "status");
  assertEq('exit on signal 9', $async->error(), "error");
}

######################################################################
# Verify that sending a SIGINT to an async sub gives the correct
# return status.
##
sub testSignalInt {
  my ($self) = assertNumArgs(1, @_);

  my $async = Permabit::AsyncSub->new(code => sub {
                                        $SIG{INT} = 'DEFAULT';
                                        kill('INT', $PID);
                                      });
  $async->start();
  $async->wait();
  assertEq('failure', $async->status(), "status");
  assertEq('exit on signal 2', $async->error(), "error");
}


######################################################################
# Verify expected signals are caught.
##
sub testExpectedSignal {
  my ($self) = assertNumArgs(1, @_);

  my $async = Permabit::AsyncSub->new(code => sub {
                                        $SIG{INT} = 'DEFAULT';
                                        kill('INT', $PID);
                                      },
                                      expectedSignals => [ 'SIGINT' ]
                                     );
  $async->start();
  $async->wait();
  assertEq('signal', $async->status(), "status");
  assertEqualNumeric(2, $async->signal(), "signal");
}

######################################################################
# Test that we fail if Data::Dumper::Terse is set.
##
sub testTerseDumper {
  my ($self) = assertNumArgs(1, @_);

  local $Data::Dumper::Terse = 1;
  my $async = Permabit::AsyncSub->new(code => sub { return 1; });
  $async->start();
  $async->wait();
  assertEq("failure", $async->status());
  $self->assert_matches(qr/internal asyncsub error/, $async->error());

  $async = Permabit::AsyncSub->new(code => sub { die("OOPS"); });
  $async->start();
  $async->wait();
  assertEq("failure", $async->status());
  $self->assert_matches(qr/internal asyncsub error/, $async->error());
}

1;
