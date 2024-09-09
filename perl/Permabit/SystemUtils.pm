##
# C<Permabit::SystemUtils> provides wrappers around system utilities
# to make them safer and easier to use.
#
# @synopsis
#
#        use Permabit::SystemUtils qw(assertSystem rsync ssh);
#
#        ssh('farm-20', 'rm /tmp/file2');
#        my @at@srcFiles = ("/tmp/foo", "/var/tmp/bar");
#        rsync([@at@srcFiles], 'farm-20', '/tmp/newDir');
#        rsync('/tmp/foo', 'farm-20', '/tmp/newDir');
#        assertSystem('rm /var/tmp/bar');
#
# @description
#
# "Permabit::SystemUtils" provides utility methods for safely calling
# the perl I<system> method.  It also includes a functional interface
# to several system tools to provide a simpler and safer mechanism for
# invoking them.
#
# $Id$
##
package Permabit::SystemUtils;

use strict;
use warnings FATAL => qw(all);
use Carp qw(croak confess);
use Cwd qw(abs_path);
use English qw(-no_match_vars);
use File::Basename;
use File::Path;
use File::Temp qw(tempdir tempfile);
use Log::Log4perl;
use Permabit::Assertions qw(
  assertDefined
  assertEq
  assertEqualNumeric
  assertFalse
  assertFileDoesNotExist
  assertMinArgs
  assertMinMaxArgs
  assertNumArgs
  assertNumDefinedArgs
  assertTrue
);
use Permabit::Constants;
use Permabit::SSHMuxIPCSession;
use Permabit::SystemUtils::Implementation;
use Permabit::Utils qw(
  getUserName
  makeFullPath
  makeRandomToken
  retryUntilTimeout
  timeToText
);
use Scalar::Util qw(blessed);
use String::ShellQuote;
use Sys::Hostname;

use base qw(Exporter);

our @EXPORT_OK = qw(
  $PYTHON_PREFIX
  assertCommand
  assertCp
  assertQuietCommand
  assertScp
  assertSystem
  athinfo
  checkResult
  copyRemoteFilesAsRoot
  cp
  createPublicDirectory
  createRemoteFile
  dropCaches
  getHardwareInfo
  getHWRaidDeviceName
  getHostNetworkState
  getNfsTempDir
  getNfsTempFile
  getScamVar
  hasPythonStackTrace
  inflateTarball
  isHWRaid
  isXen
  logCommandResults
  logOutput
  machineType
  mv
  printPerformanceResults
  pythonCommand
  relink
  resultErrors
  rsync
  runCommand
  runPkill
  runQuietCommand
  runSystemCommand
  runVirtualMachineCommand
  scp
  slurp
  ssh
  startTcpdump
  touch
  waitForListener
  waitForMachines
  waitForResult
  writePidFile
);

our $VERSION = 1.0;

# Log4perl Logging object
my $log = Log::Log4perl->get_logger(__PACKAGE__);

# Environment-specific implementation.
our $IMPLEMENTATION;

############################################################################
# Return the instance which provides the Configured controlled functionality.
#
# @return the Configured functional instance
##
sub _getImplementation {
  if (!defined($IMPLEMENTATION)) {
    $IMPLEMENTATION = Permabit::SystemUtils::Implementation->new();
  }

  return $IMPLEMENTATION;
}

#############################################################################
# Command line options passed to rsync.  Not currently configurable.
###
my $RSYNC_OPTIONS = "-e ssh -a -L";

#############################################################################
# There's no particular reason for choosing this exact number but we've
# seen through experience that ~110M of data was oom-killing our tests and
# any command that is producing a ton of data should probably reconsider
# how it's being run so as not to bloat log files.
###
our $MAX_CMD_OUTPUT = 5 * $MB;

#############################################################################
# Prefix for running python commands.
##
our $PYTHON_PREFIX = "/usr/bin/env PYTHONDONTWRITEBYTECODE=true";

#############################################################################
# Can be set to the maximum number of seconds that a local command will be
# allowed to run.  Local commands are executed directly by _doSystem(), and
# indirectly by assertSystem or runSystemCommand.
##
our $doSystemTimeout = undef;

###########################################################################
# Executes the given command on the specified host and verify that it
# succeeds, returning the command results.  All commands are logged.
# Commands are properly quoted for remote execution.
#
# @param host           The host to run the command on.
# @param cmd            The command to execute.
# @oparam sshOpts       Extra options to pass to ssh for connection-time
#
# @return       the hashref resulting from runCommand
#
# @croaks if the command had a non-zero exit code
##
sub assertCommand {
  my $result = runCommand(@_);
  checkResult($result);
  return $result;
}

###########################################################################
# Executes the given command on the specified host and verify that it
# succeeds, returning the command results.  No commands are logged unless
# there is an error.  Commands are properly quoted for remote execution.
#
# @param host  The host to run the command on.
# @param cmd   The command to execute.
#
# @return the hashref resulting from runCommand
#
# @croaks if the command had a non-zero exit code
##
sub assertQuietCommand {
  my ($host, $cmd) = assertNumArgs(2, @_);
  my $result = runCommand($host, $cmd, undef, 0);
  checkResult($result);
  return $result;
}

#############################################################################
# Run a system command and verify that it succeeds, returning its results.
#
# @param any    All arguments will be passed directly to runSystemCommand().
#
# @return       the hashref resulting from runSystemCommand
##
sub assertSystem {
  my $result = runSystemCommand(@_);
  checkResult($result);
  return $result;
}

######################################################################
# Run an athinfo query on a remote machine.
#
# @param host   The host to run the query on
# @param query  The athinfo query to run
#
# @return If called in a scalar context, returns the raw output of
#         athinfo. If called in an array context, splits that output
#         by newline. If the query times out, nothing will be returned.
##
sub athinfo {
  my ($host, $query) = assertNumArgs(2, @_);
  my $result = runSystemCommand("timeout 30 athinfo $host $query");
  return wantarray ? split("\n", $result->{stdout}) : $result->{stdout};
}

#############################################################################
# Check the result struct for a _doSystem() return and error string if
# appropriate
#
# @param result         The result hash for the call.
#
# @return a nonempty error string if there was a failure
##
sub resultErrors {
  my ($result) = assertNumArgs(1, @_);

  assertDefined($result);

  if ($result->{returnValue} != 0) {
    my $msg = "$result->{commandName} failed. ";

    if ($result->{returnValue} < 0) {
      $msg .= "(invocation) errno=$result->{errno}";
    } elsif ($result->{returnValue} > 0) {
      $msg .= "retval=$result->{status}";
    }
    chomp($result->{stdout});
    chomp($result->{stderr});
    $msg .= ", command: [ $result->{commandString} ]";
    $msg .= ", stdout: [ $result->{stdout} ], stderr: [ $result->{stderr} ]";
    return $msg;
  } else {
    return "";
  }
}

#############################################################################
# Check the result struct for a _doSystem() call and confess/croak if necessary
#
# @param result         The result hash for the call.
#
# @croaks if the command had a non-zero exit code.
##
sub checkResult {
  my ($result) = assertNumArgs(1, @_);
  assertDefined($result);
  assertNoSSHMuxError($result);
  my $msg = resultErrors($result);
  if ($msg) {
    croak($msg);
  }
}

#############################################################################
# Check the result struct for a _doSystem() call and confess if there was a
# SSHMux session error.  This assertion is buried in an extra level of
# subroutine so that "assertNoSSHMuxError" will show up in the stack trace.
#
# @param result  The result hash for the call.
#
# @croaks if the command had a SSHMux session error
##
sub assertNoSSHMuxError {
  my ($result) = assertNumArgs(1, @_);
  if (defined($result->{SSHMuxError})) {
    confess($result->{SSHMuxError});
  }
}

######################################################################
# Return debugging information on the network state.
#
# @param host   host on which to get network data
#
# @return string containing what commands were run and what the results were.
##
sub getHostNetworkState {
  my ($host) = assertNumArgs(1, @_);
  my $cmd    = '/permabit/build/tools/lastrun/getNetworkState.sh';
  my $header = "\n*****\nRunning $cmd on $host\n";
  my $result = runCommand($host, $cmd)->{stdout};
  return "${header}${result}\n";
}

#############################################################################
# Run a subroutine with a temporary public umask.
#
# @param sub        subroutine to run
#
# @return       return value from sub
##
sub _runWithPublicUmask {
  my ($sub) = assertNumArgs(1, @_);
  my $oldUmask = umask(0000);
  my $ret;
  eval {
    $ret = $sub->();
  };
  my $error = $EVAL_ERROR;
  umask($oldUmask);
  if ($error) {
    die($error);
  }
  return $ret;
}

#############################################################################
# The root of nfs temporary directories.
#
# @return       the path to the root of temporary NFS files
##
sub _getNfsTempRoot {
  assertNumArgs(0, @_);
  my $prefix = $ENV{SHARED_NFS_PREFIX} || "/permabit/not-backed-up";
  my $sub = sub {
    my $dir = "$prefix/test/" . getUserName();
    mkpath($dir, 0, 0777);
    return $dir;
  };
  return _runWithPublicUmask($sub);
}

#############################################################################
# Returns the path of a unique temporary directory on nfs and creates
# the parent directories if needed.
#
# @oparam prefix  prefix to use for the directory name
#
# @return        the path to the temporary directory
##
sub getNfsTempDir {
  my ($prefix) = assertMinMaxArgs(['getNfsTempDir'], 0, 1, @_);
  my $sub = sub {
    my $parentDir = _getNfsTempRoot();
    mkpath($parentDir, 0, 0777);
    return tempdir($prefix . "XXXXXXXXXX", DIR => $parentDir, CLEANUP => 1);
  };
  return _runWithPublicUmask($sub);
}

#############################################################################
# Returns the path of a unique temporary file on nfs and creates the parent
# directory if needed.
#
# @oparam prefix  prefix to use for the file name
#
# @return        the path to the temporary file
##
sub getNfsTempFile {
  my ($prefix) = assertMinMaxArgs(['getNfsTempFile'], 0, 1, @_);
  my $sub = sub {
    my $parentDir = _getNfsTempRoot();
    mkpath($parentDir, 0, 0777);
    my ($fh, $ret) = tempfile($prefix . "XXXXXXXXXX",
                              DIR    => $parentDir,
                              UNLINK => 1);
    close($fh);
    return $ret;
  };
  return _runWithPublicUmask($sub);
}

##########################################################################
# Return the value of a scam setting for a given host.
#
# @param host   The host to retrieve the scam variable value from
# @param var    The scam variable to retrieve the value for
#
# @return       The value of the retrieved variable. Empty string if no
#               scam value is set.
##
sub getScamVar {
  my ($host, $var) = assertNumArgs(2, @_);
  my $result = assertCommand($host, "/sbin/scam $var");
  chomp($result->{stdout});
  return $result->{stdout} || "";
}

######################################################################
# Return the device name for a megaraid volume if one exists on a given
# host.
#
# @param host   The host
##
sub getHWRaidDeviceName {
  my ($host) = assertNumArgs(1, @_);
  return getScamVar($host, 'MEGARAID');
}

######################################################################
# Check if a machine has hardware raid.
#
# @param host   The host
##
sub isHWRaid {
  my ($host) = assertNumArgs(1, @_);
  # use !! to force boolean context
  return !!getHWRaidDeviceName($host);
}

#############################################################################
# Log and run a system command and return all output.
#
# @param  command    The command to run; if an array ref, the elements of the
#                    array will be joined with spaces
# @oparam doLogging  If true, log errors and results
#
# @return A hashref containing all results of the system call.  Keys
#         are 'commandName', 'commandString', 'wrappedCommand', 'errno'
#         'returnValue', 'status', 'signal', 'dumped', 'stdout', and 'stderr'.
##
sub _doSystem {
  my ($commandString, $doLogging) = assertMinMaxArgs([1], 1, 2, @_);

  if (ref($commandString) eq 'ARRAY') {
    $commandString = join(' ', @{$commandString});
  }

  if ($doLogging) {
    $log->debug("_doSystem: running: $commandString");
  }

  my ($stdoutFH, $stdoutFile) = tempfile(SUFFIX => '.out', UNLINK => 1);
  my ($stderrFH, $stderrFile) = tempfile(SUFFIX => '.err', UNLINK => 1);

  my @files      = ($stdoutFile, $stderrFile);
  my $wrappedCmd = $commandString;
  if ($doSystemTimeout) {
    $wrappedCmd = "timeout $doSystemTimeout $wrappedCmd";
  }
  $wrappedCmd = "{\n $wrappedCmd \n} > $stdoutFile 2> $stderrFile";
  my $retval  = system($wrappedCmd); # XXX On Squeeze this will run /bin/dash
  my $result  = { };                 # but is that ok for the majority
                                     # of tests?
  # ignoring cases where command isn't first
  $result->{commandName}    = (split(' ', $commandString))[0];
  $result->{commandString}  = $commandString;
  $result->{wrappedCommand} = $wrappedCmd;
  $result->{returnValue}    = $retval;
  $result->{stdout}         = "";
  $result->{stderr}         = "";

  if ($retval < 0) {
    $result->{errno} = $ERRNO;
    close($stdoutFH);
    close($stderrFH);
    unlink(@files);
    return $result;
  }

  ($result->{status}, $result->{signal}, $result->{dumped})
    = decodeSystemRetval($retval);

  if (!(_safeRead($stdoutFH, \$result->{stdout})
        && _safeRead($stderrFH, \$result->{stderr}))) {
    logCommandResults($result, "_doSystem");
    close($stdoutFH);
    close($stderrFH);
    unlink(@files);
    croak("too much output produced running '$commandString'");
  }

  close($stdoutFH);
  close($stderrFH);
  unlink(@files);
  return $result;
}

############################################################################
# Only read up to MAX_CMD_OUTPUT bytes of a filehandle and stuff it into
# a buffer. We've found perl to behave erratically when trying to stuff
# huge amounts of data into a single scalar.
#
# @param fh         An open file handle.
# @param buffer     A reference to a scalar to store the data in.
#
# return true if all the bytes fit into the buffer.
##
sub _safeRead {
  my ($fh, $buffer) = assertNumArgs(2, @_);
  read($fh, $$buffer, $MAX_CMD_OUTPUT);
  if (!eof($fh)) {
    $$buffer .= "\n[...TRUNCATED...]";
    return;
  }
  return 1;
}

############################################################################
# Log the results of a _doSystem() invocation to the log, using error and
# debugging levels as appropriate.
#
# @param result     a hash reference to the result structure returned by
#                   _doSystem().
#
# @oparam prefix     an optional string prefix for the log messages.
# @oparam prefixAllLines whether to add the prefix to every line in
#                        stdout/stderr
#
##
sub logCommandResults {
  my ($result, $prefix, $prefixAllLines)
    = assertMinMaxArgs([ "", 0 ], 1, 3, @_);

  assertDefined($result, "result");
  if ($prefix) {
    $prefix .= ": ";
  }

  if ($result->{returnValue} < 0) {
    my $msg = "could not run command '$result->{commandString}': " .
      "$result->{errno}";
    $log->error($prefix . $msg);
    return;
  }

  if ($result->{signal}) {
    my $msg = "command died on signal $result->{signal}";
    if ($result->{dumped}) {
      $msg .= " (core dumped)";
    }
    $log->error($prefix . $msg);
  }

  if ($result->{status}) {
    my $msg = "command exited with status $result->{status}";
    $log->debug($prefix . $msg);
  }

  if ($prefixAllLines) {
    $result->{stdout} =~ s/^/$prefix/smg;
    $result->{stderr} =~ s/^/$prefix/smg;
  }
  logOutput($prefix, "stdout", $result->{stdout});
  logOutput($prefix, "stderr", $result->{stderr});
}

######################################################################
# log command output, if any, in a pretty manner
#
# @param  prefix The prefix to log
# @param  source The source of the output to log
# @param  output The output to log
# @oparam level  The level to log at.
##
sub logOutput {
  my ($prefix, $source, $output, $level)
    = assertMinMaxArgs(['debug'], 3, 4, @_);

  if ($output) {
    chomp($output);
    my @lines = split("\n", $output);
    if (scalar(@lines) > 1) {
      $output = "\n  " . join("\n  ", @lines) . "\n";
    } else {
      $output .= ' ';
    }
    $log->$level("$prefix$source: [ $output]");
  }
}

######################################################################
# returns ("Cygwin", "Sun", "Linux") if the machine is one of our
# (windows, solaris, linux) boxes
#
# @param machine  the host to query.
##
sub machineType {
  my ($machine) = assertNumArgs(1, @_);
  my $info;

  assertDefined($machine);
  if ($machine->isa('Permabit::RemoteMachine')) {
    $machine->runSystemCmd('uname -s');
    $info = $machine->getStdout();
  } else {
    my $result = runCommand($machine, 'uname -s', undef, 0);
    $info = $result->{stdout};
  }

  # WARNING: SFU and Cygwin both have uname;
  # this || takes care of either case
  if ($info =~ /^CYGWIN/ || $info =~ /^Windows/) {
    return "Cygwin";
  } elsif ($info =~ /^Sun/) {
    return "Sun";
  } elsif ($info =~ /^Linux/) {
    return "Linux";
  }
  $log->warn("Unknown machine type: $info");
  return "Unknown";
}

###########################################################################
# Convert a return value into its component parts.
#
# @param  retval    the non-negative return value of a system() invocation
#
# @return the tuple (status, signal, dumped) broken out from that retval
##
sub decodeSystemRetval {
  assertNumDefinedArgs(1, @_);
  my ($retval) = @_;

  my $status = $retval >> 8;
  my $signal = $retval & 127;
  my $dumped = $retval & 128;

  return ($status, $signal, $dumped)
}

###########################################################################
# Executes the given command repeatedly until the result condition
# subroutine returns true or the timeout expires.  Commands are properly
# quoted for remote execution.
#
# @param host     The name or address of the host to run the command on.
# @param cmd      The command string to pass to runCommand
# @param cond     A hashref to a subroutine taking a runCommand
#                 result object as its parameter, which returns true
#                 when we're done.
# @param timeout  A timeout in seconds.
# @param errmsg   A message which is part of the croak when we time out.
# @return         The hashref resulting from runCommand
##
sub waitForResult {
  my ($host, $cmd, $cond, $timeout, $errmsg) = assertNumArgs(5, @_);

  my $expiration = time() + $timeout;

  do {
    my $ret = runCommand($host, $cmd);
    if ($cond->($ret)) {
      return $ret;
    }
    sleep(1);
  } while (time() < $expiration);
  croak("timeout after " . timeToText($timeout) . ": $errmsg");
}

###########################################################################
# Executes the given command on the specified host, returning the command
# results. All commands are logged.  Commands are properly quoted for remote
# execution if needed. Note that this method may break for users whose shell is
# not bash.
#
# @param  host       The host to run the command on
# @param  cmd        The command to execute; if an array ref, the elements of
#                    the array will be joined with spaces
# @oparam sshOpts    Extra options to pass to ssh for connection-time
# @oparam doLogging  If true, log errors and results
# @oparam prefix     Optional logging prefix
#
# @return the hashref resulting from _doSystem()
##
sub runCommand {
  my ($host, $cmd, $sshOpts, $doLogging, $prefix)
    = assertMinMaxArgs([undef, 1, 'runCommand'], 2, 5, @_);
  assertDefined($host);
  assertFalse(blessed($host)); # host must be a String, not a UserMachine

  if ($host eq 'localhost') {
    return runSystemCommand($cmd, $doLogging);
  }

  if (ref($cmd) eq 'ARRAY') {
    $cmd = join(' ', @{$cmd});
  }

  $prefix = "$host: $prefix";
  if ($doLogging) {
    $log->debug("$prefix: $cmd");
  }

  if (!defined($sshOpts)) {
      $sshOpts = '';
  }

  if (!$sshOpts || $sshOpts !~ /(^|\s)-l /) {
    # Set the user based on the environment. This allows users whose shell
    # is not bash to have an alternate login with bash as its shell.
    $sshOpts .= ' -l ' . ($ENV{USER} || $ENV{LOGNAME});
  }

  my $SSHMuxError = undef;
  my $logError = sub {
    $SSHMuxError = "error in subsidiary SSHMuxIPCSession: @_";
    if ($doLogging) {
      $log->error("runCommand: $SSHMuxError");
    }
  };

  my $session = Permabit::SSHMuxIPCSession->new(hostname   => $host,
                                                sshConArgs => $sshOpts,
                                                sshRunArgs => '-n',
                                                handler    => $logError);
  if (!defined($session)) {
    return {
            status        => 255,
            returnValue   => 1,
            signal        => 0,
            dumped        => 0,
            commandString => $cmd,
            commandName   => (split(' ', $cmd))[0],
            stdout        => "",
            stderr        => "couldn't create sshmux session",
            SSHMuxError   => $SSHMuxError,
           };
  }
  my $result = {$session->send($cmd)};
  $session->close();

  $result->{SSHMuxError} = $SSHMuxError;
  $result->{commandName} = (split(' ', $cmd))[0];
  $result->{commandString} = $cmd;
  $result->{returnValue} = $result->{errno};
  ($result->{status}, $result->{signal}, $result->{dumped}) =
    decodeSystemRetval($result->{errno});

  if ($doLogging) {
    logCommandResults($result, $prefix);
  }

  return $result;
}

###########################################################################
# Construct a properly-prefixed python command invocation by injecting
# $PYTHON_PREFIX so that no intermediate byte code files are written.
#
# @param script   The python script to run
# @param args     A string containing additional arguments to the script.
# @param useSudo  If true, construct the command to use sudo.
#
# @return A string which can be used to invoke the script.
##
sub pythonCommand {
  my ($script, $args, $useSudo) = assertMinMaxArgs([0], 2, 3, @_);
  my $sudo = $useSudo ? "sudo " : "";
  return "$sudo$PYTHON_PREFIX $script $args";
}

#############################################################################
# Check whether the output text looks like it could contain a Python
# stack trace.
#
# @param text  The text to search
#
# @return  0 if the text definitely doesn't contain a stack trace, 1
#          otherwise
##
sub hasPythonStackTrace {
  my ($text) = assertNumArgs(1, @_);
  if ($text =~ m/File ".*", line [0-9]+, in/) {
    return 1;
  }
  return 0;
}

###########################################################################
# Executes the pkill command and ignores errors if the process is not found.
#
# @param host      The host to run the command on.
# @param argument  The arguments to be passed to pkill.
#
# @return The results of the pkill call.
##
sub runPkill {
  my ($host, $argument) = assertNumArgs(2, @_);
  return runCommand($host, "sudo pkill $argument");
}

###########################################################################
# Executes the given command on the specified host, returning the command
# results.  No commands are logged.  Commands are properly quoted for
# remote execution.
#
# @param host  The host to run the command on.
# @param cmd   The command to execute.
#
# @return the hashref resulting from runCommand
##
sub runQuietCommand {
  my ($host, $cmd) = assertNumArgs(2, @_);
  return runCommand($host, $cmd, undef, 0);
}

###########################################################################
# Executes the given system call, returning the command
# results.  All commands are logged.
#
# @param  cmd          Will be passed to _doSystem().
# @oparam doLogging    whether to do any logging of the command
#
# @return       the hashref resulting from _doSystem()
##
sub runSystemCommand {
  my ($cmd, $doLogging) = assertMinMaxArgs([1], 1, 2, @_);

  my $result = _doSystem($cmd, $doLogging);
  if ($doLogging) {
    logCommandResults($result, 'runSystemCommand');
  }
  return $result;
}

#############################################################################
# Rsync a file or list of files to a remote directory and verify all
# copies succeed.  All files will end up in the same directory.
#
# @param sourceFile     Either a single file or a reference to a list of
#                       files to be rsynced to the remote host
# @param host           The name of the machine to copy files to
# @param destDir        The directory on the remote machine to copy
#                       all files into
# @oparam destFile      Either a single filename or a reference to a list
#                       of files names that the files should be named as
#                       on the remote machine.  Only the basename portion
#                       of the file will be used.
##
sub rsync {
  my ($sourceFile, $host, $destDir, $destFile) = assertMinMaxArgs(3, 4, @_);
  assertCommand($host, "mkdir -p $destDir");
  # Check if sourceFile is an array ref
  my @sourceFiles
    = (ref($sourceFile) eq 'ARRAY') ? @{$sourceFile} : ($sourceFile);
  # Figure out what dest file names to use
  my @destFiles
    = $destFile
      ? ((ref($destFile) eq 'ARRAY') ? @{$destFile} : ($destFile))
      : @sourceFiles;
  for(my $i = 0; $i < scalar(@sourceFiles); $i++) {
    my $destName = makeFullPath($destDir, basename($destFiles[$i]));
    assertSystem("rsync $RSYNC_OPTIONS '$sourceFiles[$i]' '$host:$destName'");
  }
}

#############################################################################
# Perform a ssh and verify that it succeeds.
#
# @param any    All arguments will be passed directly to ssh
##
sub ssh {
  assertMinArgs(2, @_);
  assertSystem("ssh $SSH_OPTIONS @_");
}

#############################################################################
# Copy files with scp
#
# @param any    Passed to scp
##
sub scp {
  assertMinArgs(1, @_);
  return runSystemCommand("scp $SCP_OPTIONS @_");
}

######################################################################
# Check whether the named machine might be in the cloud. Err in the
# affirmative direction.
#
# @param hostname     The name of the host in question
#
# @return   True if it is not clearly a non-cloud machine
##
sub _mightBeCloudMachine {
  return _getImplementation()->mightBeCloudMachine(@_);
}

######################################################################
# Copy files from a remote directory as root.
#
# @param hostname       The host to copy from
# @param sourceDir      The directory where to start copying from
# @param files          The files or directories to copy from sourceDir
# @param targetDir      Where to write it on the local host.
##
sub copyRemoteFilesAsRoot {
  my ($hostname, $sourceDir, $files, $targetDir) = assertNumArgs(4, @_);
  # Sometimes the remote machine can just write directly to NFS,
  # without having to go through the testing host.
  #
  # Only short-cut in certain cases: Our standard NFS directories, and
  # neither host in the cloud. (Cloud machines can access most of our
  # NFS directories but it'll be less efficient, and not all NFS
  # directories are shared with the office network. On the other hand,
  # if both machines are in the cloud and accessing the same NFS
  # directory in the office, we still could distribute the writing.)
  if (!_mightBeCloudMachine($hostname) && !_mightBeCloudMachine(hostname())) {
    my $fullTargetDir = abs_path($targetDir);
    if ($fullTargetDir =~ m|^/permabit/|) {
      # For paranoia, make sure the remote host can see the target
      # directory. (It could fail in certain NFS caching cases.)
      my $result = runCommand($hostname, "test -d $fullTargetDir");
      if ($result->{returnValue} == 0) {
        runCommand($hostname,
                   "sudo tar cf - -C $sourceDir $files "
                   . "| tar xf - -C $fullTargetDir");
        return;
      }
    }
  }
  runSystemCommand("ssh $SSH_OPTIONS $hostname"
                   . " sudo tar cf - -C $sourceDir $files"
                   . " | tar xf - -C $targetDir");
}

#############################################################################
# Copy files with scp or die on error.
#
# @param any    Passed to scp
##
sub assertScp {
  assertMinArgs(1, @_);
  assertSystem("scp $SCP_OPTIONS @_");
}

#############################################################################
# Copy files preserving attributes.
#
# @param any    Passed to cp
##
sub cp {
  assertMinArgs(1, @_);
  return runSystemCommand("cp -p " . join(" ", @_));
}

######################################################################
# Move the given file.
#
# @param origFile       The file to be moved.
# @param dest           The destination
##
sub mv {
  my ($origFile, $dest) = assertNumArgs(2, @_);
  return runSystemCommand("mv $origFile $dest");
}

#############################################################################
# Copy files preserving attributes or die on error.
#
# @param any    Passed to cp
##
sub assertCp {
  assertMinArgs(1, @_);
  assertSystem("cp -p " . join(" ", @_));
}

#############################################################################
# Atomically change an existing symlink to point somewhere else.  The
# existing symlink is changed to be owned by the current user.
#
# @param existingSymlink  An existing symlink
# @param newTarget        The location that the symlink should be atomically
#                         changed to point at.
# @croaks If the existing symlink wasn't changed to the new target.
##
sub relink {
  my ($existingSymlink, $newTarget) = assertNumArgs(2, @_);
  my $user = getUserName();
  runSystemCommand("sudo chown $user $existingSymlink");
  symlink($newTarget, "$existingSymlink-tmp");
  rename("$existingSymlink-tmp", $existingSymlink);
  assertEq(readlink($existingSymlink), $newTarget);
}

######################################################################
# Create a file on the given host with the given contents.
#
# @param host           The host to create the file on
# @param contents       The contents of the file to be created
# @oparam file          The path to the remote file to create
# @oparam owner         The owner of the file.  Defaults to the current user.
# @oparam mode          The mode of the file to explicitly set.
#
# @return
##
sub createRemoteFile {
  my ($host, $contents, $file, $owner, $mode) = assertMinMaxArgs(2, 5, @_);
  $owner ||= getUserName() . ":staff";

  # create temp file locally
  my ($fh, $tmpFile) = tempfile();
  print $fh $contents;
  close($fh) || croak("Couldn't close temporary file $tmpFile: $ERRNO");

  my $remoteTmp = "/tmp/crf$UID" . makeRandomToken(10);

  assertScp($tmpFile, "$host:$remoteTmp");
  unlink($tmpFile);
  if ($file) {
    assertCommand($host, "sudo mv $remoteTmp $file");
  } else {
    $file = $remoteTmp;
  }
  assertCommand($host, "sudo chown $owner $file");

  if (defined($mode)) {
    assertCommand($host, "sudo chmod $mode $file");
  }

  return $file;
}

######################################################################
# Send a command to a virtual machine through the VM controller.
#
# @param hostname  Hostname of the virtual machine
# @param command   The command to send
##
sub runVirtualMachineCommand {
  _getImplementation()->runVirtualMachineCommand(@_);
}

######################################################################
# Wait for a list of machines to respond to ping, ssh and ntp
#
# @param waitTime0  How long to wait before checking for ping
# @param pingTime   Maximum time to wait for ping
# @param waitTime1  How long to wait after ping and before ssh checks
# @param sshTime    Maximum time to wait for ssh
# @param hostnames  list of hostnames
#
# @croaks if any of the machines fail to respond to ping or ssh with
# in the specified maxtimes.
##
sub waitForMachines {
  my ($waitTime0, $pingTime, $waitTime1, $sshTime, @hostnames)
    = assertMinArgs(4, @_);
  $log->debug("Waiting " . timeToText($waitTime0)
              . " before pinging machines.");
  sleep($waitTime0);

  $log->debug("Using ping to see which machines have come back alive.");
  # Wait for machines to come back alive.
  foreach my $hostname (@hostnames) {
    _waitForMachinePing($pingTime/20, $pingTime, $hostname);
  }
  $log->debug("Sleeping for " . timeToText($waitTime1)
              . " to let ssh start up");
  sleep($waitTime1);
  foreach my $hostname (@hostnames) {
    _waitForMachineSSH($sshTime/20, $sshTime, $hostname);
  }
}

######################################################################
# Wait for the given hostname to respond to pings
#
# @param waitTime   How long to wait between checks
# @param maxTime    The maximum time to wait
# @param hostname   The hostname of the machine you are waiting on
#
# @croaks if the maximum ping time is exceeded
##
sub _waitForMachinePing {
  my ($waitTime, $maxTime, $hostname) = assertNumArgs(3, @_);
  my $startTime = time();
  while (1) {
    my $pingResult = `ping -c 1 $hostname`;
    if ($pingResult !~ /0 received/) {
      return;
    }
    sleep($waitTime);
    my $period = time() - $startTime;
    assertTrue($period < $maxTime,
               "waitForMachinePing($hostname) failed after "
               . timeToText($period) . ".");
  }
}

######################################################################
# Wait for the given hostname to respond to SSH and establish a primary
# timeserver.
#
# @param waitTime   How long to wait between checks
# @param maxTime    The maximum time to wait
# @param hostname   The hostname of the machine you are waiting on
#
# @croaks if more than $maxTime seconds elapses without being able to ssh
#         to the machine.
##
sub _waitForMachineSSH {
  my ($waitTime, $maxTime, $hostname) = assertNumArgs(3, @_);
  my $startTime = time();
  my $error;
  while (1) {
    my $result
      = runCommand($hostname,
                   '/sbin/scam --test VIRTUAL'
                   . ' || (timedatectl status'
                   . '     | egrep "(NTP|System clock) synchronized: yes")');
    if ($result->{returnValue} == 0) {
      return;
    } elsif ($result->{returnValue} > 0 && $result->{status} == 255) {
      $error = "couldn't ssh to $hostname yet";
    } else {
      $error = "we think ssh is up but ntp isn't"
    }
    $log->debug(resultErrors($result));
    $log->debug("$error -- sleeping for " . timeToText($waitTime) . " more.");
    sleep($waitTime);
    my $period = time() - $startTime;
    assertTrue($period < $maxTime,
               "waitForMachineSSH($hostname) failed after "
               . timeToText($period));
  }
}

######################################################################
# Create a world-writable directory (and all higher levels).
#
# @param path           Path to directory
##
sub createPublicDirectory {
  my ($path) = assertNumArgs(1, @_);
  return _runWithPublicUmask(sub {
                               mkpath($path, 0, 0777);
                             });
}

##########################################################################
# Run tcpdump on a host and wait for it to begin running
#
# @param  hostname     The hostname to run tcpdump on
# @param  expression   The tcpdump expression to run
# @param  dir          A directory for the dump files.
#
# @return the paths of the dump file and stderr file.
##
sub startTcpdump {
  my ($host, $expression, $dir) = assertNumArgs(3, @_);

  my $dumpFile = "$dir/tcpdump.dump";
  my $errFile  = "$dir/tcpdump.err";

  $log->debug("starting tcpdump on host $host");

  # Do this first, so the file always exists by the time we run "tail".
  runCommand($host, "cp /dev/null $errFile");
  my $cmd = "sudo tcpdump -i any -f -n -w $dumpFile $expression >$errFile 2>&1";
  runCommand($host, "$cmd &"); # Start tcpdump in background
  my $waitSub
    = sub {
      my $result = runCommand($host, "tail $errFile");
      return $result->{stdout} =~ /^tcpdump: listening/;
    };
  retryUntilTimeout($waitSub, "tcpdump failed to startup", $MINUTE);
  return ($dumpFile, $errFile);
}

######################################################################
# Print a pretty table of performance results
#
# @param  res      The result object
# @param  log      The log object
# @oparam subcase  Name to appear in parens after results if needed
##
sub printPerformanceResults {
  my ($res, $log, $subcase) = assertMinMaxArgs(2, 3, @_);
  if (defined($subcase)) {
    $subcase = " ($subcase)";
  } else {
    $subcase = "";
  }
  $log->info("Printing performance results$subcase");
  my $scanRateMB = $res->{'scan rate'} / $MB;
  $log->info("Scan Rate (MB/s): $scanRateMB");
  my $avgTurnTime = $res->{'total turnaround time'} / $res->{'requests'};
  $log->info("Average Turnaround Time (usec): $avgTurnTime");
}

######################################################################
# Gather information about the hardware.
#
# @param host   the host to get information about
#
# @return hashref of hardware information
##
sub getHardwareInfo {
  my ($host) = assertNumArgs(1, @_);
  my $retval = {};
  my $result = assertCommand($host, "grep MemTotal /proc/meminfo");
  if ($result->{stdout} =~ /^MemTotal:\s*(\d+)\s*kB/) {
    $retval->{"Main memory"} = $1;
  }
  $result = assertCommand($host, "grep processor /proc/cpuinfo | wc -l");
  if ($result->{stdout} =~ /(\d+)/) {
    $retval->{"Number of processors"} = $1;
  }
  $result = assertCommand($host, "awk 'BEGIN { tot=0 } "
                                 .    "/^cpu cores/ { tot += \$4 } "
                                 .    "END { print tot; }' /proc/cpuinfo");
  if ($result->{stdout} =~ /(\d+)/) {
    $retval->{"Number of cores"} = $1;
  }
  $result = assertCommand($host, "grep 'cpu MHz' /proc/cpuinfo");
  if ($result->{stdout} =~ /cpu MHz\s*(.*)/) {
    $retval->{"Processor speed"} = $1;
  }
  $result = assertCommand($host, "grep 'model name' /proc/cpuinfo");
  if ($result->{stdout} =~ /model name\s*:\s*(.*)/) {
    $retval->{"Process model"} = $1;
  }
  return $retval;
}

######################################################################
# Wait for a listener port to be established
#
# @param host  listening host
# @param port  port number
##
sub waitForListener {
  my ($host, $port) = assertNumArgs(2, @_);
  $log->info("Waiting for listener on host $host port $port");
  my $waiter = sub {
    my $result = runCommand($host, "netstat --listening --tcp -n");
    return (($result->{status} == 0)
            && grep { /\s0\.0\.0\.0:$port\s/} split(/^/, $result->{stdout}));
  };
  retryUntilTimeout($waiter, "No listener on $host:$port", $MINUTE);
}

#############################################################################
# Try to flush the buffer cache, to avoid reading directly from memory.
#
# @param  host        The host to flush.
# @oparam mountpoint  The mountpoint to unmount and remount.
##
sub dropCaches {
  my ($host, $mountpoint) = assertMinMaxArgs([undef], 1, 2, @_);

  if ($mountpoint) {
    # Remount with this mechanism:
    #
    # - Scan /proc/mounts for existing mount information
    # - Parse the mount info to get mount device and mount options
    # - Umount
    # - Mount using the previously gathered mount information.
    #
    # The above procedure handles mount points that aren't registered in
    # /etc/fstab.  Also, it handles cases where /etc/mtab has been linked
    # to /proc/mounts instead.
    #
    # (An alternative solution would have been to umount without updating
    # /etc/mtab, so that the latter information could be used to remount.
    # However, that approach can't work if /etc/mtab is not a true external
    # file and is instead linked to /proc/mounts. )

    # Get mount parameters for mounted filesystem from /proc/mounts.  Use
    # this instead of information from /etc/mtab since the format of the
    # latter can vary depending on whether it is maintained as an external
    # file or is a symbolic link to /proc/mounts.
    my $result = runCommand($host, "cat /proc/mounts | grep $mountpoint");
    my @fields = split(/\s+/, $result->{stdout});
    assertEqualNumeric((scalar @fields), 6);
    my $deviceName = $fields[0];
    my $mountOptions = $fields[3];

    assertCommand($host, "sudo umount $mountpoint");
    assertCommand($host, "sudo mount $deviceName $mountpoint -o $mountOptions");
  }
  assertCommand($host, "sync; sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'");
}

#############################################################################
# Untar a specific tarball.
#
# @param host          target machine name
# @param tarballName   tarball to inflate
# @param path          path to the tarball
##
sub inflateTarball {
  my ($host, $tarballName, $path) = assertNumArgs(3, @_);
  # If $unpacked exists then the tarball was already unpacked.
  # Otherwise, create empty $unpacked file and unpack the tarball.
  # This tar --transform moves all files from bin/ and drivers/
  # to the top level directory and -z means gunzip the .tar.gz file.
  my $tarFile = makeFullPath($path, $tarballName);
  my $unpacked = "$tarFile.unpacked";
  my $alreadyUnpacked = runCommand($host, "test -e $unpacked");
  if ($alreadyUnpacked->{returnValue} != 0) {
    assertCommand($host, "touch $unpacked");
    my $regex = 's%\(.*bin/\)\|\(.*drivers/\)%%';
    my $tarCmd = "cd $path && tar --transform \'$regex\' -zxf $tarFile";
    assertCommand($host, $tarCmd);
    assertCommand($host, "ls -la $path");
  }
}

######################################################################
# Given a string suitable for "open", reads the entrire contents into
# an array of lines.
#
# @param pipeString The string describing the data source.
#
# @return An array of lines read.
##
sub slurp {
  my ($pipeString) = @_;
  my @lines;
  open(my $fh, $pipeString) or confess("unable to open '$pipeString'");
  while (my $line = <$fh>) {
    chomp($line);
    push(@lines, $line);
  }
  close($fh) or confess("unable to close filehandle for '$pipeString'");
  return @lines;
}

######################################################################
# Touches a file
#
# @param file   A filename to touch
##
sub touch {
  my ($file) = assertNumArgs(1, @_);

  my $now = time;
  utime(undef, undef, $file)
    || open(my $TMP, ">>$file")
    || $log->warn("Couldn't touch $file: $ERRNO");
  if (defined $TMP) {
    close($TMP);
  }
}

######################################################################
# Writes our pid to a file.
#
# @param file   A filename to write the pid to.
##
sub writePidFile {
  my ($file) = assertNumArgs(1, @_);
  if (-e $file) {
    # Pid file already exists. Check if it's a valid pid.
    open(my $fh, '<', "$file");
    my $pid = <$fh>;
    chomp($pid);
    if ($pid ne '' and system("kill -0 $pid 2> /dev/null") == 0) {
      $log->logcroak("Pidfile $file exists and contains an existing "
        . "pid($pid). Exiting.");
    }
    close($fh);
  }
  open(my $fh, '>', "$file");
  $log->debug("Writing out pid($PID) to $file.");
  print $fh $PID or $log->logcroak("Can't write to $file: $OS_ERROR");
  close($fh);
}

1;
