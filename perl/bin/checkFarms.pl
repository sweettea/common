#!/usr/bin/perl

##
# Check the current status of machines (and optionally fix them).
#
# @synopsis
#
# checkFarms.pl [--exec PROGRAM] [--skip HOST[,HOST...]] [--verbose]
#               [--reserveAndFixOnFailure] [--all] [HOST[,HOST...]]
#
# @level{+}
#
# @item B<--exec> PROGRAM
#
# Run the given program to check hosts instead of using "athinfo HOST
# checkserver".  The program must be specified via an absolute path
# and NFS accessible on all hosts.  Its output must be in the same
# format as the checkServer.pl script.  In fact, it usually is a
# custom version of the checkServer script that is being tested. By
# default this script only runs checkServer on unreserved machines.
#
# @item B<--skip> HOST[,HOST...]
#
# Do not check the given hosts.
#
# @item B<--all>
#
# Check all machines (even ones that are already reserved)
#
# @item B<--verbose>
#
# Be more verbose about what is being done
#
# @item B<--reserveAndFixOnFailure>
#
# Try to reserve and fix machines with certain kinds of problems (by
# running the PROGRAM mentioned above as sudo and passing it the --fix
# argument). (Note: forces --batchSize to '1')
#
# @item B<--batchSize>
#
# Sets how many machines to check at once.  Default is 20. When
# --reserveAndFixOnFailure is set batchSize must be equal to 1.
#
# @item [HOST[,HOST...]]
#
# An optional list of machines to check.  Defaults to checking all
# machines in RSVP except for windows and solaris machines.
#
# @level{-}
#
# @description
#
# This script is used to check the status of machines to ensure that
# they don't break tests that run on them.  It runs the checkServer.pl
# script on each host and verifies that no illegal processes are
# running on each.
#
# $Id$
##

use FindBin;
use lib "${FindBin::RealBin}/../lib";

use diagnostics;
use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Getopt::Long;
use Log::Log4perl qw(:easy);
use Pdoc::Generator qw(pdoc2help pdoc2usage);
use Time::HiRes qw(usleep);
use Permabit::Assertions qw(assertNumArgs assertGENumeric);
use Permabit::AsyncSub;
use Permabit::Constants;
use Permabit::RSVP;
use Permabit::SystemUtils qw(runSystemCommand);
use Permabit::Utils qw(canonicalizeHostname getScamVar);

my $log;
my $SSH = "ssh -T -o ConnectTimeout=10 $SSH_OPTIONS ";

my @TABOO_PS = ();
my %PS_COMMANDS = (linux        => '/bin/ps auxww',
                  );
#XXX: This should be updated to use /usr/bin/checkServer.pl once we establish
#     symlinks in the lab to point at the /permabit/build location.
my $DEFAULT_CHECKSERVER = '/permabit/build/tools/lastrun/checkServer.pl';
my $MAX_FAILURES = 0;

my @skipList = ();
my $checkScript = $DEFAULT_CHECKSERVER;
my $all = 0;
my $reserveAndFixOnFailure = 0;
my $leakCount = 0;
my $maxTasks = 30;

main();
exit(0);

######################################################################
# The main body.
##
sub main {
  parseArgs();
  my $rsvp = new Permabit::RSVP();
  my @hosts = (@ARGV) ? @ARGV : getMachineList($rsvp, \@skipList);

  # check all the machines for goodness
  my %tasks;
  my ($counter, $lastCount, $failCount) = (0, 0, 0);
  while (keys(%tasks) != 0 || @hosts != 0) {
    if (@hosts != 0 && scalar(keys(%tasks)) < $maxTasks) {
      # Take the last element from the list because this is typically how
      # RSVP hands out new assigments so these hosts will have the highest
      # churn. Since we cache the owner from RSVP once, we should try and
      # check the machines with the high churn first.
      my ($host, $owner) = @{pop(@hosts)};
      if ($owner && !$all) {
        $log->debug("$host is reserved by $owner -- skipping");
        next;
      }
      my $code = sub {
        my $message = "";
        my $checkServerMsg = doCheckServer($host, $owner, 0);
        my $checkProcessesMsg = checkProcesses($host, $owner);
        if ($checkServerMsg && !$checkProcessesMsg && $reserveAndFixOnFailure) {
          $message = reserveAndFix($rsvp, $host, $checkServerMsg, $owner);
        } else {
          $message = "$checkServerMsg$checkProcessesMsg" || "ok";
        }
        return "${host}: $message";
      };
      $tasks{$host} = Permabit::AsyncSub->new(code            => $code,
                                              killOnDestroy   => 1,
                                              signalOnDestroy => "KILL",);
      $tasks{$host}->start();
      # Stagger the spawning of jobs so they don't all hit RSVP at once.
      usleep(10_000);
    }

    while(my ($host, $task) = each(%tasks)) {
      if ($task->isComplete()) {
        eval {
          my $res = $task->result();
          if ($res =~ /release failed|not fixed/) {
            $leakCount++;
          }
          if ($res ne "$host: ok") {
            # Since we don't actually reserve the machines while we check them
            # because this would slow down the test too much and add it would
            # exercise RSVP too much, it's possible for a test to have grabbed
            # the machine and caused it to fail so we should ignore the cases
            # where we think that happened.
            my $owner = getOwner($rsvp, $host);
            if ($owner) {
              $log->info("$host: ignoring failure as it is now reserved "
                         . "by $owner");
            } else {
              ++$failCount;
            }
          }
          $log->info($res);
        };
        if ($EVAL_ERROR) {
          $log->warn($EVAL_ERROR);
        }
        delete($tasks{$host});
      }
    }

    if ($reserveAndFixOnFailure && $leakCount >= 3) {
      $log->logcroak("Called with reserveAndFixOnFailure and "
                   . "$leakCount machines failed to fix/release.  Aborting");
    }
    $counter++;
    if ($counter % 3_000 == 0) {
      my $remaining = scalar(@hosts) + scalar(keys(%tasks));
      $log->info("Machines remaining: " . $remaining);
      if (($remaining < 10) && ($remaining > 0)) {
        $log->info("Hosts in progress: " . join(' ', keys(%tasks)));
        if ($lastCount == $remaining) {
          $log->logcroak("Giving up on: " . join(' ', keys(%tasks)));
        }
      }
      $lastCount = $remaining;
    }
    usleep(10_000);
  }
  $rsvp->close();
  assertGENumeric($MAX_FAILURES, $failCount,
                  "too many machines failed checkServer");
  $log->info("Done.");
}

######################################################################
# Try to reserve, fix, and release the machine unless
# a) the machine is not under control of rsvp.
# b) a user is (or just was) using the machine.
# c) if we have already leaked machines by trying to fix them.
#
# This method will not clean up process problems, only checkServer
# problems.
#
# @param rsvp    The Permabit::RSVP object to use
# @param host    The host to fix
# @param message The message that checkServer returned before which is
#                why we are trying to fix the machine.
# @param user    The user that is or was just using this machine.
#
# @return A suitable error or success message.
##
sub reserveAndFix {
  my ($rsvp, $host, $message, $user) = assertNumArgs(4, @_);
  if ($user) {
    return "$message\n$host: already reserved by $user, will not fix.";
  }
  $log->info("$host: trying to reserve and fix these errors $message");
  eval {
    $rsvp->reserveHostByName(host => $host, msg  => "checkFarms fix");
  };
  if ($EVAL_ERROR) {
    return "reserve failed";
  }
  doCheckServer($host, $user, 1);
  my $msg = doCheckServer($host, $user, 0);
  if ($msg) {
    return "not fixed $msg";
  }
  eval {
    $rsvp->releaseHost(host => $host)
  };
  if ($EVAL_ERROR) {
    return "release failed";
  }
  return "ok";
}

######################################################################
# Parse command line options.
##
sub parseArgs {
  my $verbose = 0;
  if (!GetOptions(
         "help!"                   => sub { pdoc2help(); },
         "exec=s"                  => \$checkScript,
         "skip=s"                  => \@skipList,
         "all"                     => \$all,
         "verbose!"                => \$verbose,
         "batchSize=i"             => \$maxTasks,
         "reserveAndFixOnFailure!" => \$reserveAndFixOnFailure,
                 )) {
    pdoc2usage();
  }

  Log::Log4perl->easy_init({layout => '%m%n',
                            level  => $verbose ? $DEBUG : $INFO,
                            file   => "STDOUT"});
  $log = Log::Log4perl->get_logger(__PACKAGE__);

  if ($checkScript !~ m|^/|) {
    pdoc2usage();
  }

  if ($reserveAndFixOnFailure) {
    $log->info("Detected 'reserveAndFixOnFailure' "
             . "stepping down to batchSize of '1'");
    $maxTasks = 1;
  }

  # Handle arguments of the form '--skip=foo,bar'
  @skipList = split(/,/, join(',', @skipList));
}

######################################################################
# Get the machines to check.  Returns a combination of the live
# machines in RSVP and some other machines we specially care about.
#
# @param rsvp           The Permabit::RSVP object to use
# @param excludeList    A listref of machines to exclude from the list
#
# @return A list of [hostname, owner] arrays to check
##
sub getMachineList {
  my ($rsvp, $excludeList) = assertNumArgs(2, @_);
  my @machines = ();

  # Get current user for hosts
  my $list = $rsvp->listHosts(verbose   => 1);
  foreach my $info (@{$list}) {
    $info->[1] ||= "";
    if (($info->[1] ne "DEATH") && !grep(/^$info->[0]$/, @{$excludeList})) {
      push(@machines, [$info->[0], $info->[1]]);
    }
  }
  return @machines;
}

######################################################################
# Get user who has the given machine reserved, or an empty string if
# it's not reserved or not in RSVP.
#
# @param rsvp           The Permabit::RSVP object to use
# @param host           The hostname to get the owner of
#
# @return The user who has the machine reserved
##
sub getOwner {
  my ($rsvp, $host) = assertNumArgs(2, @_);
  my $list = $rsvp->listHosts(verbose   => 1, hostRegexp => $host);
  if (scalar(@{$list}) == 0) {
    return '';
  } elsif (scalar(@{$list}) == 1) {
    return $list->[0]->[1] || '';
  } else {
    die("Multiple machines in RSVP matched $host???");
  }
}

######################################################################
# Run the checkserver command via athinfo or ssh.
#
# TODO: Research if using Permabit::Machine stops us from getting
#       hung up on broken machines.
#
# @param host   The machine to check
# @param user   The user who has the machine reserved, if any
# @param fix    If true, fix the machine if possible.
#
# @return An error message or the empty string
##
sub doCheckServer {
  my ($host, $user, $fix) = assertNumArgs(3, @_);
  my $cmd
    = $checkScript eq $DEFAULT_CHECKSERVER
      ? "athinfo $host checkserver"
      : "$SSH$host $checkScript";
  if ($fix) {
    $cmd = "$SSH$host sudo $checkScript --fix";
  }
  my $result = runSystemCommand($cmd);
  if ($result->{stdout} =~ /^success$/) {
    return "";
  }
  my @warnings = split(/\n/, $result->{stdout} . $result->{stderr});
  return "(" . join(", ", @warnings) . ")";
}

######################################################################\
# Check for any illegal processes on the given host via ssh.
#
# @param host   The machine to check
# @param user   The user who has the machine reserved, if any
#
# @return An error message or the empty string
##
sub checkProcesses {
  my ($host, $user) = assertNumArgs(2, @_);

  my $cmd = getPSCommand($host);
  my $result = runSystemCommand("$SSH$host '$cmd'");
  if ($result->{returnValue} != 0) {
    return " ssh failed";
  }
  if (!$user) {
    foreach my $p (@TABOO_PS) {
      if ($result->{stdout} =~ /\W$p\s/) {
        return " illegal process: $p";
      }
    }
  }
  return "";
}

######################################################################
# Return the ps command for the given host, based on its machine type.
#
# @param host   The host to get the ps command for
#
# @return The ps command appropriate for the given machine.
##
sub getPSCommand {
  my ($host) = assertNumArgs(1, @_);
  if (isWindows($host)) {
    return $PS_COMMANDS{'windows'};
  } elsif (isSolaris($host)) {
    return $PS_COMMANDS{'solaris'};
  }
  return $PS_COMMANDS{'linux'};
}

######################################################################
# Return whether or not the given machine is a windows box.
#
# @param host   The host to check
#
# @return A true value if the machine is a windows box, false otherwise
##
sub isWindows {
  my ($host) = assertNumArgs(1, @_);
  $host = canonicalizeHostname($host);
  return system("innetgr -h $host windows") == 0;
}

######################################################################
# Return whether or not the given machine is a solaris box.
#
# @param host   The host to check
#
# @return A true value if the machine is a solaris box, false otherwise
##
sub isSolaris {
  my ($host) = assertNumArgs(1, @_);
  $host = canonicalizeHostname($host);
  return system("innetgr -h $host solaris") == 0;
}
