##
# Test of Proc::Simple package
#
# $Id$
##
package testcases::ProcSimpleTest;

use strict;
use warnings FATAL => qw(all);
use Carp;
use English qw(-no_match_vars);
use Log::Log4perl;
use Proc::Simple;
use Time::HiRes qw(usleep);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
##
sub testPollExitStatus {
  my ($self) = @_;

  $log->info("testPollExitStatus");

  for my $i (1 .. 1) {
    print ".";
    my $p = Proc::Simple->new();
    $p->start(sub { usleep(2 * 1000 * 1000); });
    while ($p->poll()) {
      usleep( 1000);
    }
    $self->assert( defined($p->exit_status()),
                   "exit status should be defined");
  }
  print "\n";
}

######################################################################
##
sub testPollExitStatus2 {
  my ($self) = @_;

  $log->info("testPollExitStatus2");

  my @procs;
  for my $i (1 .. 100) {
    my $p = Proc::Simple->new();
    $p->start(sub { usleep(10 * 1000 * 1000); });
    push(@procs, $p)
  }

  while (1) {
    my $p = shift(@procs);
    if (!$p->poll()) {
      $self->assert( defined($p->exit_status()),
                     "exit status should be defined");
    } else {
      push @procs, $p;
    }
    usleep( 100 * 1000);
    print ".";
    if (@procs == 0) {
      last;
    }
  }
  print "\n";
}
1;
