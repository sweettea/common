##
# Utility functions for manipulating processes.
#
# @synopsis
#
#     use Permabit::ProcessUtils qw(
#       descendants
#       startSubsInParallel
#       waitForSubs
#     );
#
#     my $subRoutines = [\&sub1, \&sub2];
#     my $procArray = startSubsInParallel($subRoutines);
#     my $passed = waitForSubs($procArray);
#
#     my @childProcs = descendants($PID);
#
# @description
#
# C<Permabit::ProcessUtils> provides utility methods for working with
# processes.  It provides a functional interface to these methods due
# to their static nature.
#
# $Id$
##
package Permabit::ProcessUtils;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

# The testing framework may use a string with a function name to be run
# so we need to make sure it is allowed.
no strict "refs";

use Carp qw(confess croak);
use Log::Log4perl;
use Permabit::Assertions qw(assertMinArgs assertMinMaxArgs assertNumArgs);
use Permabit::Constants;
use POSIX;
use Proc::Simple;
use Time::HiRes qw(usleep);

use base qw(Exporter);

our @EXPORT_OK = qw (
  checkSubStatus
  delayFailures
  descendants
  killSubs
  parent
  runSubsInParallel
  startSubsInParallel
  waitForSubs
);

our $VERSION = 1.0;

my $log = Log::Log4perl->get_logger(__PACKAGE__);

# Default polling interval for runSubsInParallel() is 1s
my $DEFAULT_POLLING_INTERVAL = 1 * 1000 * 1000;

############################################################################
# Checks the array of executing subroutines to see if any of them have
# completed, and what their exit status was.
#
# @param    procs  An array ref of SimpleProcs to inspect, as returned by
#                 startSubsInParallel.
#
# @return   A list whose first element is an integer that's true if any of the
#         subs had errors. The second element is a ref to the list of subs
#         that are still active.
##
sub checkSubStatus {
  my ($procsRef) = assertNumArgs(1,@_);

  my $hasErrors = 0;
  my @procs2 = ();

  foreach my $proc (@{$procsRef}) {
    #warning: (!defined($proc->exit_status())) is not a
    #reliable way to tell if the process has terminated
    if ($proc->poll()) {
      #hasn't terminated yet
      push(@procs2, $proc);
    } else {
      if (!defined($proc->exit_status())) {
        $hasErrors += 0.01;
      } elsif ($proc->exit_status() != 0) {
        $hasErrors += 1.00;
      }
    }
  }

  return ($hasErrors, \@procs2);
}

##########################################################################
# Return a hash ref of child and parent processes
#
# @return hash ref of current parent->[children,] processes
##
sub _getChildHash {
  my %children;
  open(TABLE, "ps h -e -o pid,ppid |");
  while (<TABLE>) {
    my ($child, $ppid) = split(" ", $_);
    if (!exists($children{$ppid})) {
      $children{$ppid} = [ ];
    }
    push(@{$children{$ppid}}, $child);
  }
  close(TABLE);
  return \%children;
}


##########################################################################
# Return an array of the pids of all descendants of the given processes.
#
# @param PIDS   The pids whose descendants to find.
#
# @return An array of child pids
##
sub descendants {
  my @PIDS = assertMinArgs(1, @_);
  my $children = _getChildHash();
  #collect the descendant pids with a bfs
  my %seen;
  while (@PIDS != 0) {
    my $parent = shift(@PIDS);
    my $kids = $children->{$parent} || [ ];
    foreach my $kid (@{$kids}) {
      $seen{$kid}++;
    }
    push(@PIDS, @{$kids});
  }
  return keys(%seen);
}

##########################################################################
# Return the pid of the given process' parent 
#
# @param pid   The pid whose parent to find.
#
# @return the parent pid found, or zero
##
sub parent {
  my ($pid) = assertNumArgs(1, @_);
  my $children = _getChildHash();
  foreach my $key (keys %{$children}) {
    if (scalar (grep (/^$pid$/, @{$children->{$key}}))) {
      return $key;
    }
  }
  return 0;
}

############################################################################
# Kills all of the executing subroutines in the array
#
# @param procs            An array ref of SimpleProcs to kill, as
#                         returned by startSubsInParallel.
##
sub killSubs {
  my ($procArray, $signal) = assertMinMaxArgs(['SIGTERM'], 1, 2, @_);
  foreach my $proc (@{$procArray}) {
    $proc->kill($signal);
  }
  # XXX: This should potentially check to make sure the processes
  # actually died
}

######################################################################
# Run the given list of subroutines in parallel, with an optional
# polling interval. Returns true if no subroutine died/croaked.
#
# This can only be used if the Proc::Simple package is in the @INC
# path, which means running out of a built src/perl tree.
#
# @param subsToRun         Listref of the subroutines to run.
# @param timeout           Time in seconds before wait aborts and kills
#                          all subroutines.
# @oparam pollingInterval  Polling interval in microseconds
# @oparam commonArg        Argument to pass to all subs
#
# @return  true if the all of the subroutines were successful, else false
##
sub runSubsInParallel {
  my ($subsToRun, $timeout, $pollingInterval, $commonArg)
    = assertMinMaxArgs([$DEFAULT_POLLING_INTERVAL, undef], 2, 4, @_);

  my $procArray = startSubsInParallel($subsToRun, $commonArg);
  return waitForSubs($procArray, $pollingInterval, $timeout);
}

############################################################################
# Start the given list of subroutines in parallel, with an optional
# polling interval. Returns the array of Procs that can be polled via
# checkSubStatus to determine when the subroutines have completed.
#
# @param  subsToRun  Listref of the subroutines to run.
# @oparam commonArg  Argument to pass to all subs
#
# @return An array ref of Procs that can be polled for completion status.
##
sub startSubsInParallel {
  my ($subsToRun, $commonArg) = assertMinMaxArgs([undef], 1, 2, @_);

  my @procs;
  # fire up each subroutine
  foreach my $sub (@{$subsToRun}) {
    my $wrappedSub = sub {
      my $ret = 1;
      eval {
        $sub->($commonArg);
      };
      if ($EVAL_ERROR) {
        $ret = 0;
        my $msg = "Child process threw: $EVAL_ERROR";
        $log->debug($msg);
      }

      # hard exit so destructors don't fire in the child process
      if ($ret == 0) {
        POSIX::_exit(1);
      } else {
        POSIX::_exit(0);
      }
    };

    my $proc = Proc::Simple->new();
    $proc->start($wrappedSub);
    push(@procs, $proc);
  }

  return \@procs;
}

############################################################################
# Waits for all of the executing subroutines in the array to complete
# and returns their exit status.  Optionally will timeout and kill all
# subroutines after a given interval.
#
# @param procs            An array ref of SimpleProcs to inspect, as
#                         returned by startSubsInParallel.
# @oparam pollingInterval Polling interval in microseconds
# @oparam timeout         Time in seconds before wait aborts and kills
#                         all subroutines.  Defaults to
#                         $Permabit::Constants::FOREVER.
#
# @return true if the all of the subroutines were successful, else
# false
##
sub waitForSubs {
  my ($procArray, $pollingInterval, $timeout) =
    assertMinMaxArgs([$DEFAULT_POLLING_INTERVAL, $FOREVER], 1, 3, @_);

  # poll subroutines for termination
  my $allPassed = 1;
  my $timeTaken = 0;
  while (@{$procArray} != 0) {
    usleep($pollingInterval);

    (my $hadErrors, $procArray) = checkSubStatus($procArray);
    if ($hadErrors) {
      $allPassed = 0;
    }

    $timeTaken += $pollingInterval / 1000 / 1000;
    if ($timeout != $FOREVER) {
      my $livingSubs = (@{$procArray});
      if (($timeTaken > $timeout) && $livingSubs) {
        killSubs($procArray);
        croak("$livingSubs still alive after $timeTaken s");
      }
    }
  }

  return $allPassed;
}

#############################################################################
# Run a series of synchronous subs, logging a failure when one dies.  But we
# execute every sub, and then die with the real failure
#
# @param steps  The subs to run (in order).  May be an empty list.
#
# @croaks if any of the steps fail
##
sub delayFailures {
  my @steps = @_;
  my @errors;
  foreach my $step (@steps) {
    eval { $step->(); };
    if ($EVAL_ERROR) {
      push(@errors, $EVAL_ERROR);
      $log->error("DELAYED FAILURE: $errors[-1]");
    }
  }
  if (scalar(@errors) == 1) {
    # If we got exactly one error, rethrow it now.
    die(@errors)
  } elsif (scalar(@errors) > 1) {
    # If we get more than one error, assemble an error message out of the first
    # line of each error string.
    confess(join("\n", scalar(@errors) . " delayed failures:",
                 map { (split("\n"))[0] } @errors));
  }
}

1;
