##
# Base class for checkServer tests.
#
# $Id$
##
package CheckServer::Test;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;
use Log::Log4perl::Level;

use Permabit::Assertions qw(
  assertMinArgs
  assertMinMaxArgs
  assertNumArgs
);
use Permabit::AsyncSub;
use Permabit::SystemUtils qw(
  resultErrors
  runSystemCommand
);

use base qw(CheckServer::Delegator);

use overload q("") => \&toString;

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# Create a new test and register it with the framework.
##
sub new {
  my ($pkg, $framework, %arguments) = assertMinArgs(2, @_);
  my $self = $pkg->SUPER::new($framework,
                              async     => 0,
                              done      => 0,
                              error     => '',
                              fixes     => [],
                              framework => $framework,
                              %arguments);
  $framework->addTest($self);
  return $self;
}

########################################################################
# Get the name of this test.
#
# @return The test name
##
sub name {
  my ($self) = assertNumArgs(1, @_);
  my $name = ref($self);
  $name =~ s/^.*:://;
  return $name;
}

########################################################################
# Record an error for this test.
#
# @param error    The error to record
# @oparam reboot  If true, suggest a reboot
##
sub fail {
  my ($self, $error, $reboot) = assertMinMaxArgs([0], 2, 3, @_);
  if ($self->{error}) {
    $self->{error} = join("\n", $self->{error}, $error);
  } else {
    $self->{error} = $error;
  }

  if ($reboot) {
    $self->suggestReboot();
  }
}

########################################################################
# Record a set of commands to run in order to fix problems found by this test.
#
# @param commands  The commands to run
##
sub addFixes {
  my ($self, @commands) = assertMinArgs(1, @_);
  push(@{$self->{fixes}}, @commands);
}

######################################################################
# Add fixes to rebuild the given file via /permabit/mach/Makefile.
#
# @param  file       The file to rebuild
# @oparam noVarConf  Set to true if /var/conf should not be consulted, defaults
#                    to false
##
sub rebuildFromMach {
  my ($self, $file, $noVarConf) = assertMinMaxArgs([0], 2, 3, @_);
  $self->addFixes($self->SUPER::rebuildFromMach($file, $noVarConf));
}

########################################################################
# Check whether this test passed.
#
# @return True if the test failed
##
sub passed {
  my ($self) = assertNumArgs(1, @_);
  return ($self->{error} eq '');
}

########################################################################
# Report the failure message.
##
sub report {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{error}) {
    $log->warn($self->{error});
  }
}

########################################################################
# A filter to determine whether this test should be skipped. By default,
# returns false. Tests should override this method if they should not always be
# run.
#
# @return false if the test should be run
##
sub skip {
  my ($self) = assertNumArgs(1, @_);
  return 0;
}

########################################################################
# Run this test.
##
sub run {
  my ($self) = assertNumArgs(1, @_);
  if (!$self->{async}) {
    $self->runSynchronously();
    return;
  }

  $self->{asyncSub} = Permabit::AsyncSub->new(code => sub {
                                                $self->runSynchronously();
                                                return $self
                                              });
  $self->{asyncSub}->start();
}

########################################################################
# Run this test syncrhonously
##
sub runSynchronously {
  my ($self) = assertNumArgs(1, @_);
  eval {
    $self->test();
  };
  if ($EVAL_ERROR) {
    $self->fail($EVAL_ERROR);
  }

  $self->{done} = 1;
}

########################################################################
# The actual test to perform, derived classes must override this method.
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  $self->fail($self->name() . "::test() unimplemented");
}

########################################################################
# Wait until this test is complete.
##
sub wait {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{done}) {
    return;
  }

  if ($self->{asyncSub}) {
    my $result = $self->{asyncSub}->result();
    $self->fail($result->{error});
    $self->addFixes(@{$result->{fixes}});
    $self->{done} = 1;
    return;
  }

  if ($self->{async}) {
    die("wait() called on non-running test $self");
  }

  die("wait() called on incomplete synchronous test $self");
}

########################################################################
# Fix the issues found by this test.
#
# @param dryRun  If true, just report the fix, don't do it.
##
sub fix {
  my ($self, $dryRun) = assertNumArgs(2, @_);
  my $fixed = 0;
  my $commandLogger = Log::Log4perl->get_logger("Permabit::SystemUtils");
  my $level = $commandLogger->level();

  $commandLogger->level($DEBUG);
  foreach my $fix (@{$self->{fixes}}) {
    if ($dryRun) {
      $log->info("Would have performed fix: $fix\n");
    } else {
      $self->runCommand($fix);
    }
    $fixed++;
  }

  $commandLogger->level($level);
  return $fixed;
}

########################################################################
# Run a command and return its output. Fail the test if the command fails.
#
# @param  command       The command to run
# @oparam continuation  Any number of additional parts of the command
#
# @return The output of the command
##
sub assertCommand {
  my ($self, @command) = assertMinArgs(2, @_);
  my $result = runSystemCommand(join(' ', @command));
  my $error  = resultErrors($result);
  if ($error) {
    $self->fail($error);
  }

  return (wantarray ? split("\n", $result->{stdout}) : $result->{stdout});
}

########################################################################
# Open a file. Fail the test if we can't.
#
# @param file  The file to open
#
# @return A handle to the file
##
sub open {
  my ($self, $file) = assertNumArgs(2, @_);
  my $fh = IO::File->new($file);
  if (!defined($fh)) {
    $self->fail("$self: Couldn't open $file: $ERRNO");
  }

  return $fh;
}

########################################################################
# Open a file. Fail the test and abort it if we can't.
#
# @param file  The file to open
#
# @return A handle to the file
##
sub openOrAbort {
  my ($self, $file) = assertNumArgs(2, @_);
  my $fh = $self->open($file);
  if (!defined($fh)) {
    croak();
  }

  return $fh;
}

########################################################################
# Read a file. If this fails, fail the test and abort.
#
# @param file  The file to read
#
# @return The contents of the file either as an array of lines or a string
#         depending on what wantarray says
##
sub readFileOrAbort {
  my ($self, $file) = assertNumArgs(2, @_);
  my @lines = $self->openOrAbort($file)->getlines();
  return (wantarray ? @lines : join('', @lines));
}

########################################################################
# Open a directory. Fail the test if we can't.
#
# @param dir  The directory to open
#
# @return A handle to the directory
##
sub openDir {
  my ($self, $dir) = assertNumArgs(2, @_);
  my $dh = IO::Dir->new($dir);
  if (!defined($dh)) {
    $self->fail("$self: Couldn't open $dir: $ERRNO");
  }

  return $dh;
}

########################################################################
# Open a directory. If we can't, fail the test and abort.
#
# @param dir  The directory to open
#
# @return A handle to the directory
##
sub openDirOrAbort {
  my ($self, $dir) = assertNumArgs(2, @_);
  my $dh = $self->openDir($dir);
  if (!defined($dh)) {
    croak();
  }

  return $dh;
}

########################################################################
# Overload default stringification.
##
sub toString {
  my ($self) = assertNumArgs(3, @_);
  return $self->name();
}

1;

