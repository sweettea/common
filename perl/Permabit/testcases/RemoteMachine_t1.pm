##
# Test basic functions of the Permabit::RemoteMachine module.
#
# $Id$
##
package testcases::RemoteMachine_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Log::Log4perl;
use Permabit::Assertions qw(
  assertEq
  assertEqualNumeric
  assertNENumeric
  assertNumArgs
  assertTrue
);
use Permabit::SystemUtils qw(assertSystem);

use base qw(testcases::RemoteMachineBase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

###############################################################################
# @inherit
##
sub tear_down {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{remoteFiles}) {
    # Remote files might have white space in their names
    my @files = map { "'$_'" } @{$self->{remoteFiles}};
    my $remover = sub { $self->{machine}->runSystemCmd("rm -fr @files"); };
    $self->runTearDownStep($remover);
  }
  if ($self->{localFiles}) {
    my $remover = sub { assertSystem("rm -fr @{$self->{localFiles}}"); };
    $self->runTearDownStep($remover);
  }
  $self->SUPER::tear_down();
}

###############################################################################
##
sub testBasic {
  my ($self) = assertNumArgs(1, @_);
  my $machine = $self->{machine};

  $machine->runSystemCmd("true");

  my $errno = $machine->sendCommand("false");
  assertNENumeric(0, $errno, "Command 'false' failed");

  $machine->runSystemCmd("echo hi");
  assertEq("hi\n", $machine->getStdout());

  $machine->runSystemCmd("echo -n hi");
  assertEq("hi", $machine->getStdout());

  assertEq("/foo bar/foo_bar.gz",
           $machine->getSavedLogfilePath("/foo bar", "foo bar"));
}

###############################################################################
##
sub testRetrieveLogFile {
  my ($self) = assertNumArgs(1, @_);
  my $host = $self->{hostNames}[0];
  my $machine = $self->{machine};

  # create $destDir locally
  my $destDir = "/tmp/logs.$PID";
  push(@{$self->{localFiles}}, $destDir);
  mkdir($destDir);

  # original file has a space in the name; final has that changed to a '_'
  my $sourceBase = "/tmp/$PID-test";
  my $sourceFile = "$sourceBase file-$PID";
  my $destFile   = "$destDir/$host/$PID-test_file-$PID.gz";

  # create a file
  push(@{$self->{remoteFiles}}, $sourceFile);
  $machine->runSystemCmd("echo foo >'$sourceFile'");

  # retrieve the file
  $machine->retrieveLogFile($destDir, $sourceFile);

  # check that we got it
  assertTrue(-e $destFile, "failed to retrieve file");
  assertEq("foo\n", `gzip -d -c '$destFile'`);

  # check that we can find the file
  my @foundFiles = $machine->_findLogfiles("$sourceBase*");
  assertEqualNumeric(1, scalar(@foundFiles), "found wrong number of files");
  assertEq($sourceFile, $foundFiles[0],
           "failed to expand wildcard on remote system");
}

###############################################################################
# Test that getLogFileList returns an empty array if the directory
# has been cleaned up on the remote host, instead of throwing an error.
##
sub testGetLogFileList {
  my ($self) = assertNumArgs(1, @_);
  my $machine = $self->{machine};
  $machine->{logDirectory} = "/tmp/bogus$PID";
  my @lf = $machine->getLogFileList();
  assertEqualNumeric(0, scalar(@lf), "getLogFileList not empty");
}

1;
