#!/usr/bin/perl

##
# Cleanup a host and then release it via RSVP.
#
# @synopsis
#
#  cleanAndRelease.pl [--force] [--user USERNAME] [--noRelease] MACHINE...
#
# @level{+}
#
# @item B<--force>
#
# Go ahead!  Clean and release hosts that we have not reserved via RSVP.
#
# @item B<--user USERNAME>
#
# Perform release as this user.
#
# @item B<--noRelease>
#
# Don't release hosts after cleaning them up.
#
# @item MACHINE...
#
# The machines to clean and release.
#
# @level{-}
#
# @description
#
# Run forceTestCleanup.sh on each host listed and then release it from
# RSVP.
#
# $Id$
##

use strict;
use warnings FATAL => qw(all);

use FindBin;
use lib "${FindBin::RealBin}/../lib";

use Getopt::Long;
use Log::Log4perl qw(:easy);
use Pdoc::Generator qw(pdoc2help pdoc2usage);
use Permabit::RSVP;
use Permabit::Assertions qw(assertNumArgs);
use Permabit::Constants;
use Permabit::Utils qw(getUserName shortenHostName);
use Proc::Simple;
use Time::HiRes qw (usleep);

Log::Log4perl->easy_init({layout => '%m%n',
                          level  => $WARN,
                          file   => "STDOUT"});

my $user = getUserName();
chomp(my $LOCALHOST = `hostname`);
$LOCALHOST = shortenHostName($LOCALHOST);

my $CHECKSERVER_CMD = "$FindBin::Bin/checkServer.pl --fix";

######################################################################
# Clean up and release a machine.
#
# @param name           name of machine to release
# @param force          if true, do not verify reservation
# @param doRelease      if true, actually release machine.
# @param rsvpUser       the user to run rsvp as
# @param rsvp           Permabit::RSVP object
#
# @return               exits 1 on errors, 0 otherwise
##
sub doClean {
  my ($name, $force, $doRelease, $rsvpUser, $rsvp) = assertNumArgs(5, @_);

  if (!$force) {
    $rsvp->verify(host => $name,
                  user => $rsvpUser);
  }

  print "Cleaning up $name\n";
  system("ssh -A $name sudo \"$CHECKSERVER_CMD --user $rsvpUser"
         . ($force ? " --force" : "") . "\"");

  if ($doRelease) {
    print "Releasing $name\n";
    $rsvp->releaseHost(host  => $name,
                       msg   => "cleanAndRelease from $LOCALHOST",
                       force => 1,
                       user  => $rsvpUser);
  }
  exit(0);
}

######################################################################
# Main
##
my $force = 0;
my $rsvpUser = $user;
my $noRelease = 0;
if (!GetOptions(
                "force!"     => \$force,
                "user=s"     => \$rsvpUser,
                "help!"      => sub { pdoc2help(); },
                "noRelease!" => \$noRelease,
                )
    || (@ARGV == 0)) {
  pdoc2usage();
}

my @BATCH_USERS = ('continuous', 'nightly');

if ($rsvpUser ne $user) {
  if (!grep { $rsvpUser eq $_ } @BATCH_USERS) {
    print STDERR "Disallowed user: $rsvpUser, only these allowed: ",
      join(",", @BATCH_USERS), "\n";
    exit(1);
  }
}

# Start a cleanup process for each argument
my @procs;
foreach my $machine (@ARGV) {
  my $p = Proc::Simple->new(reap_only_on_poll => 1);
  my $rsvp = Permabit::RSVP->new();

  $p->start(\&doClean, $machine, $force, !$noRelease, $rsvpUser, $rsvp);
  push @procs, $p;

  $rsvp->close();
}

my $ret = 0;

# Wait for each process to finish
while (@procs != 0) {
  my $p = shift(@procs);
  if ($p->poll()) {
    push(@procs,$p);
  } elsif ($p->exit_status()) {
    $ret = 1;
  }
  usleep(100000);
}

exit($ret);
