##
# Perl module that serves as a base class for other modules that need
# to run programs on remote machines.
#
# @synopsis
#
#     use Permabit::RemoteMachine;
#
#     $server = Permabit::RemoteMachine->new(hostname => <hostname>);
#     $name = $server->getName();
#     $server->runSystemCmd("true);
#     my $errno = $server->sendCommand("false");
#     $server->sendCommand("echo hi");
#     my $output = $server->getStdout();
#     $server->saveLogFiles("/tmp/savelogs/");
#     $server->close();
#
# @description
#
# C<Permabit::RemoteMachine> provides an object oriented interface to
# running programs on a remote machine and retrieving their logfiles.
#
# $Id$
##
package Permabit::RemoteMachine;

use strict;
use warnings FATAL => qw(all);
use Carp;
use English qw(-no_match_vars);
use File::Basename;
use File::Path;
use File::Spec;
use Log::Log4perl;
use Storable qw(dclone);
use String::ShellQuote qw(shell_quote);

use Permabit::Assertions qw(
  assertDefined
  assertMinArgs
  assertMinMaxArgs
  assertNotDefined
  assertNumArgs
  assertOptionalArgs
);
use Permabit::BashSession;
use Permabit::Constants;
use Permabit::LabUtils qw(fixNextBootDevice isVirtualMachine rebootMachines);
use Permabit::SystemUtils qw(
  assertCommand
  assertSystem
  getHostNetworkState
  runCommand
);
use Permabit::Utils qw(
  makeFullPath
  makeRandomToken
  reallySleep
  removeArg
  retryUntilTimeout
);

use overload q("") => \&as_string;

# Log4perl Logging object
my $log = Log::Log4perl->get_logger(__PACKAGE__);

# A lot of our command syntax in our code depends on bashisms. We need the
# --login option to ensure proper path initialization on (some) RHEL8 hosts.
our $SHELL = '/bin/bash --login';

my $DAEMON_LOG = "/var/log/daemon.log";
my $KERN_LOG   = "/var/log/kern.log";
my $SYS_LOG    = "/var/log/syslog";
my $USER_LOG   = "/var/log/user.log";

# This is a list for maintaining Permabit::BashSession objects from parent
# processes.  We cannot just drop these on the floor, because the
# Permabit::BashSession finalizer kills the ssh process belonging to the
# session.  We keep the perl object alive forever, and leave it to the
# process that forked off the ssh process to clean it up.
my @ancestorSessions;

##
# @paramList{new}
my %PROPERTIES
  = (
     # @ple A list of subs to run to clean up the machine after use.
     _cleanupSteps    => [],
     # @ple Whether or not logfiles should be compressed when they are saved.
     compressLogs     => 1,
     # @ple Set if logfiles cannot or should not be retrieved.
     disableLogSaving => 0,
     # @ple The machine this server should be run on
     hostname         => undef,
     # @ple the max number of hung task warnings to report in kern.log
     hungTaskWarnings => 25,
     # @ple Number of times to retry opening Permabit::BashSession
     IPCRetries       => 5,
     # @ple The directory logfiles should be retrieved from
     logDirectory     => '/var/log',
     # @ple Regexp for which files in logDirectory to retrieve
     logfileRegexp    => ".*",
     # @ple last general log cursor
     _journalCursor => undef,
     # @ple last kernel log cursor
     _journalKernelCursor => undef,
     # @ple Start time for messages relevant to this RemoveMachine
     _journalStartTime => 0,
    );
##

###############################################################################
# Construct a new RemoteMachine object.
#
# @params{new}
##
sub new {
  my $self = shift;
  if (!ref($self)) {
    $self = bless { %{ dclone(\%PROPERTIES) }, @_ }, $self;
  }
  assertDefined($self->{hostname}, "Hostname not set");
  $self->openSession();
  $self->_logMachineInfo();
  $self->sendCommand("date +\%s");
  $self->{_journalStartTime} = $self->getStdout();
  chomp($self->{_journalStartTime});
  $self->initLogFileMarker();
  $self->initJournalCursors();
  fixNextBootDevice($self->getName());
  return $self;
}

###############################################################################
# Return all configurable parameters for this class
##
sub getParameters {
  assertNumArgs(0, @_);
  return [keys(%PROPERTIES)];
}

###############################################################################
# Tear down the RemoteMachine.  This method is essentially a destructor, and it
# should perform any necessary cleanup.  After this call is made, no further
# use will be made of the object.
##
sub tearDown {
  my ($self) = assertNumArgs(1, @_);
  $log->debug("$self:tearDown");
  $self->close();
  $self->cleanupFiles();
}

###############################################################################
# Start the RemoteMachine.  This method may be called more than once,
# interspersed with calls to stop().
##
sub start {
  my ($self) = assertNumArgs(1, @_);
  $self->openSession();
}

###############################################################################
# Stop the RemoteMachine.  This method should be idempotent; it may be called
# any number of times, with or without matching calls to start().  This method
# should return true iff the service was stopped or was already stopped.
#
# @return Whether the service has stopped
##
sub stop {
  my ($self) = assertNumArgs(1, @_);
  $self->close();
  return 1;
}

###############################################################################
# Create our Permabit::BashSession connection to the remote machine
##
sub openSession {
  my ($self) = assertNumArgs(1, @_);

  $log->debug("$self:openSession");
  assertNotDefined($self->{_session});

  my $cmd = "ssh $SSH_OPTIONS $self->{hostname} $SHELL ";
  my $error;
  foreach my $i (1..$self->{IPCRetries}) {
    eval {
      $self->{_session} = Permabit::BashSession->new($cmd, $self->{hostname});
    };
    if ($EVAL_ERROR) {
      $error = $EVAL_ERROR;
      $log->info("new Permabit::BashSession $cmd failed: retrying");
      if ($error =~ /Connection refused/) {
        # The remote machine may be mid-reboot.
        my $delay = 3;
        $log->debug("error was connection-refused, delaying ${delay}s");
        reallySleep($delay);
      }
    } else {
      $self->{_pid} = $PID;
      return;
    }
  }
  die($error);
}

###############################################################################
# Close any open resources. Cannot use sendCommand() after this.
##
sub close {
  my ($self) = assertNumArgs(1, @_);

  if ($self->{_pid} && $self->{_session}) {
    if ($self->{_pid} == $PID) {
      $log->debug("$self:close()");
      local $EVAL_ERROR;
      eval {
        $self->{_session}->close();
      };
      if ($EVAL_ERROR) {
        $log->warn("Problem closing Permabit::BashSession: $EVAL_ERROR");
        # Don't bother re-throwing it.
      }
    } else {
      push(@ancestorSessions, $self->{_session});
    }
  }
  $self->{_pid} = undef;
  $self->{_session} = undef;
}

###############################################################################
# Reset any session for the remote machine.
##
sub resetSession {
  my ($self) = assertNumArgs(1, @_);
  if (defined($self->{_session})) {
    $self->close();
    $self->openSession();
  }
}

###############################################################################
# Return the hostname of the remote machine.
#
# @return The hostname of this machine
##
sub getName {
  my ($self) = assertNumArgs(1, @_);
  return $self->{hostname};
}

###############################################################################
# Return the exit status of the last call to sendCommand()
#
# @return The exit status
##
sub getStatus {
  my ($self) = assertNumArgs(1, @_);
  return $self->{_session}->errno();
}

###############################################################################
# Return the output to STDERR of the last call to sendCommand()
#
# @return The output to STDERR
##
sub getStderr {
  my ($self) = assertNumArgs(1, @_);
  return $self->{_session}->stderr();
}

###############################################################################
# Return the output to STDOUT of the last call to sendCommand()
#
# @return The output to STDOUT
##
sub getStdout {
  my ($self) = assertNumArgs(1, @_);
  return $self->{_session}->stdout();
}

###############################################################################
# Log information about the capabilities of the reserved machine
##
sub _logMachineInfo {
  my ($self) = assertNumArgs(1, @_);

  # Obtain kernel architecture information
  # Includes: kernel release and processor type
  $self->sendCommand('uname -pr');
  my $arch = $self->getStdout();
  chomp($arch);

  # Obtain OS information
  # Includes: distributor ID and distribution release number
  my $command = "egrep '^(NAME|VERSION_ID)=' < /etc/os-release";
  $self->sendCommand($command);
  my $stdout = $self->getStdout();

  my ($name, $version_id);
  foreach my $line (split("\n", $stdout)) {
    if ($line =~ /^NAME=/) {
        $line =~ s/(NAME=|"|\s)//g;
        $name = $line;
    } elsif ($line =~ /^VERSION_ID=/) {
        $line =~ s/(VERSION_ID=|")//g;
        $version_id = $line;
    }
  }
  my $os = join(' ', grep { $_ } $name, $version_id);

  # Obtain date/time
  $self->sendCommand('date "+%F %T,%3N"');
  my $datetime = $self->getStdout();
  chomp($datetime);

  # Log obtained information
  $log->info("Host details for " . $self->{hostname} . ":"
             . "\n  Architecture: $arch"
             . "\n  Operating System: $os"
             . "\n  Date: $datetime");
}

###############################################################################
# Log a list of all the processes running on the machine
##
sub logProcesses {
  my ($self) = assertNumArgs(1, @_);
  $self->sendCommand("ps faux");
  my $output = $self->getStdout();
  chomp($output);
  $output =~ s/\n/\n  /g;
  $log->debug("Processes running on $self->{hostname}:\n  $output");
}

######################################################################
# Log command output, if any, in a clear manner.
#
# @param  label   The label for the output to log
# @param  output  The output to log
##
sub _logOutput {
  my ($self, $label, $output) = assertNumArgs(3, @_);

  if ($output) {
    chomp($output);
    my @lines = split("\n", $output);
    if (scalar(@lines) > 1) {
      $output = "\n  " . join("\n  ", @lines) . "\n";
    }
    $log->debug("$label: [ $output ]");
  }
}

###############################################################################
# Get a string containing the stdout/stderr output from the last command,
# indented with tabs
##
sub _getCmdOutput {
  my ($self) = assertNumArgs(1, @_);

  my $stdout = $self->getStdout();
  my $stderr = $self->getStderr();
  return "\tstdout: $stdout\n\tstderr: $stderr";
}

###############################################################################
# Run the given command on this server.
#
# @param command  The command to run
#
# @croaks if the command does not succeed
##
sub assertExecuteCommand {
  my ($self, $command) = assertNumArgs(2, @_);
  my $errno = $self->executeCommand($command);
  if ($errno) {
    confess("Failed while running $command on $self->{hostname}: $errno\n"
            . $self->_getCmdOutput());
  }
}

###############################################################################
# Run the given command on this server.
#
# @param command  The command to run
#
# @return the errno
##
sub executeCommand {
  my ($self, $command) = assertNumArgs(2, @_);
  $log->debug("$self->{hostname}: $command");
  my $errno = $self->sendCommand($command);
  $self->_logOutput("$self->{hostname}: stdout", $self->getStdout());
  $self->_logOutput("$self->{hostname}: stderr", $self->getStderr());
  return $errno;
}

###############################################################################
# Run the given command (either a string or a list of strings to be
# joined together) on this server.  Croak if the command does not
# succeed.
#
# @param cmd The command to run on the remote server
#
# @croaks if the command does not succeed
##
sub runSystemCmd {
  assertMinArgs(2, @_);
  my $self = shift;
  my $cmd = join(' ', @_);
  $log->debug("$self->{hostname}: $cmd");
  my $errno = $self->sendCommand($cmd);
  if ($errno) {
    confess("Failed while running $cmd on $self->{hostname}: $errno\n"
            . $self->_getCmdOutput());
  }
}

###############################################################################
# Run the given command on the remote machine and return the error code.
#
# @param command The command to run on the remote server
#
# @return The return code of the command
##
sub sendCommand {
  my ($self, $command) = assertNumArgs(2, @_);
  if ($self->{_pid} && ($self->{_pid} != $PID)) {
    # Some other process (which must be our ancestor in the process tree)
    # created the current Permabit::BashSession.  Preserve the old session
    # so that the ancestor can continue to use it, and create a new session
    # for our own use.
    push(@ancestorSessions, $self->{_session});
    $self->{_session} = undef;
    $self->openSession();
  }

  if (!defined($self->{_session})) {
    my $err = "no IPC Session";
    $log->error($err);
    confess($err);
  }

  # If the flush fails, the session is bad and will need to be recreated.
  eval {
    $self->{_session}->rxflush('stderr');
  };
  if ($EVAL_ERROR) {
    $self->resetSession();
  }

  return $self->{_session}->send($command);
}

###############################################################################
# Run the given command (like sendCommand) on the remote machine, log the
# output, and return the error code.
#
# @param command The command to run on the remote server
#
# @return The return code of the command
##
sub debugSendCmd {
  my $self = shift;
  $log->debug("debugSendCmd: $self running: @_");
  my $ret = $self->sendCommand(@_);
  $log->debug("debugSendCmd: $self output:\n" . $self->_getCmdOutput());
  return $ret;
}

###############################################################################
# Returns the full path of a file in the server's log directory
##
sub makeLogFilePath {
  my ($self, $fileName) = assertNumArgs(2, @_);
  return makeFullPath($self->{logDirectory}, $fileName);
}

###############################################################################
# Returns the inode of the youngest log file prior to starting the server.
##
sub getOldestLogfileInode {
  my ($self) = assertNumArgs(1, @_);
  return $self->{_oldestLogInode}
}

###############################################################################
# Sets the inode of the youngest log file that existed prior to
# starting the server.  If called before start(), it will prevent the
# inode from being updated, allowing older log files to be retrieved
# along with new ones.
##
sub setOldestLogfileInode {
  my ($self, $inode) = assertNumArgs(2, @_);
  $self->{_oldestLogInode} = $inode;
}

###############################################################################
# Save all log files to a given directory.
#
# @param saveDir  The directory in which to save the logfiles
##
sub saveLogFiles {
  my ($self, $logDir) = assertNumArgs(2, @_);
  if ($self->{disableLogSaving}) {
    return;
  }
  $logDir = File::Spec->rel2abs($logDir);
  mkpath($logDir);
  if (!-d $logDir) {
    croak("No such directory: $logDir");
  }

  my @logFiles = $self->getLogFileList();
  foreach my $file (@logFiles) {
    $self->retrieveLogFile($logDir, $file);
  }
}

###############################################################################
# Utility to save a logfile by copying it from the remote machine to a
# local directory.  Depending on whether compressLogs is set, this
# will either gzip the files or copy them back straight.  If a
# logFilePath ends with a forward-slash, then all of the files in that
# directory will be retrieved.
#
# @param logDir         The directory to save log files in.
# @param logFilePathIn  The path to the logfile to retrieve
##
sub retrieveLogFile {
  my ($self, $logDir, $logFilePathIn) = assertNumArgs(3, @_);

  my $hostDir = makeFullPath($logDir, $self->{hostname});
  mkpath($hostDir);
  foreach my $logFilePath ($self->_findLogfiles($logFilePathIn)) {
    local $EVAL_ERROR;
    my $saveLogFile;
    eval {
      # Use gzip -c so that original file isn't removed
      my $copyCommand = ($self->{compressLogs}) ? "gzip -c" : "cat";
      $saveLogFile = $self->getSavedLogfilePath($hostDir,
                                                basename($logFilePath));
      assertSystem("ssh $SSH_OPTIONS $self->{hostname} "
                   . shell_quote("sudo $copyCommand '$logFilePath'")
                   . " > '$saveLogFile'");

      # Fix the mtime of the copy
      my $result
        = assertCommand($self->{hostname},
                        qq(sudo stat -c %Y '$logFilePath'));
      my $mtime = $result->{stdout};
      chomp($mtime);
      utime($mtime, $mtime, $saveLogFile);
    };
    if (my $error = $EVAL_ERROR) {
      $log->warn("retrieveLogFile problem: $error");
      if ($error =~ /Received a SIG[^ ]+, killing/) {
        # Rethrow the error caught by eval - the original thrower has
        # already decorated the error by using croak or confess, so there
        # is no need for us to add to it
        die($error);
      }
      # rename any probably invalid .gz file
      if ($self->{compressLogs}) {
        my $errLogFile = makeFullPath(dirname($saveLogFile),
                                      'ERROR.' . basename($saveLogFile));
        if (rename($saveLogFile, $errLogFile)) {
          $log->warn("retrieveLogFile renaming '$saveLogFile' to"
                     . " '$errLogFile'");
        }
      }
    }
  }
}

###############################################################################
# Expand a file expression (files, dirs, globs) to a list of files.
#
# @param logFileGlob  Either the full path to a logfile, a directory of
#                     logs or a glob of one the above.
#
# @return A list of file paths.
##
sub _findLogfiles {
  my ($self, $logFileGlob) = assertNumArgs(2, @_);

  # Make sure spaces in filename don't break find.
  $logFileGlob =~ s/ /\\ /g;

  my $res = runCommand($self->{hostname},
                       "sudo find $logFileGlob -type f");
  return split(/\n/, $res->{stdout});
}

###############################################################################
# Return the path to a saved logfile.  Translates spaces to underscores
# in logFile but not in logDir.
#
# @param logDir  The directory to log files are saved in.
# @param logFile The name of the logfile
#
# @return A path for the saved logfile, based on original logfile name
#         and hostname.
##
sub getSavedLogfilePath {
  my ($self, $logDir, $logFile) = assertNumArgs(3, @_);
  $logFile =~ tr/ /_/;
  my $saveLogFile = makeFullPath($logDir, $logFile);
  if ($self->{compressLogs}) {
    $saveLogFile .= ".gz";
  }
  return $saveLogFile;
}

###############################################################################
# Initialize a field that tracks the most recent logfile in
# logDirectory that should be listed in getLogFileList().
##
sub initLogFileMarker {
  my ($self) = assertNumArgs(1, @_);
  if (defined($self->{_oldestLogInode})) {
    return;
  }

  my $marker = $self->makeLogFilePath("logfile.timestamp");
  $self->sendCommand("mkdir -p $self->{logDirectory}");
  $self->sendCommand("sudo \\touch $marker");
  $self->sendCommand("sudo chmod 666 $marker");
  $self->sendCommand("\\ls -1 -t --inode $marker");
  my $outputLine = $self->getStdout();
  $outputLine =~ s/^\s+//;
  my @output = split(/\s/, $outputLine);
  if (scalar(@output)) {
    $self->{_oldestLogInode} = $output[0];
  } else {
    $self->{_oldestLogInode} = -1;
  }
}

###############################################################################
# Return the list of files that have been touched in logDirectory
# since this initLogFileMarker() was called.  Clients should override
# this to return the list of all logfiles to be saved.
#
# @return A list of the full paths to the log files that have been
#         created.
##
sub getLogFileList {
  my ($self) = assertNumArgs(1, @_);

  my $result = runCommand($self->{hostname},
                          "\\ls -1 -t --inode $self->{logDirectory}");
  if ($result->{returnValue} != 0) {
    return ();
  }

  my @lines = split(/\n/, $result->{stdout});
  my @logfiles;
  foreach my $line (@lines) {
    my ($inode, $logfile) = $line =~ /(\d+)\s+(.*)/;
    if (!defined($self->{_oldestLogInode})
        || ($inode != $self->{_oldestLogInode})) {
      if ($self->shouldSaveLogFile($logfile)) {
        push(@logfiles, "$self->{logDirectory}/$logfile");
      }
    } else {
      last;
    }
  }

  if (!@logfiles) {
    # We should have generated at least 1 logfile
    $log->warn("No logfiles newer than inode "
               . (defined($self->{_oldestLogInode}) ? $self->{_oldestLogInode}
                                                    : 'undef')
               . " found:\n"
               . $result->{stdout});
  }
  return @logfiles;
}

###############################################################################
# Decide whether a file in the server logDirectory should be saved. This will
# be called by getLogFileList() for every file that has been touched in
# logDirectory since initLogFileMarker() was called. By default, all files
# matching logfileRegexp will be saved.
#
# @param logFile  The name of the file in logDirectory.
#
# @return a true value if the file should be copied
##
sub shouldSaveLogFile {
  my ($self, $logFile) = assertNumArgs(2, @_);
  return ($logFile =~ /$self->{logfileRegexp}/);
}

###############################################################################
# Return the list of files to clean up. Clients should override.
##
sub getCleanupFiles {
  my ($self) = assertNumArgs(1, @_);
  return ( );
}

###############################################################################
# Remove any temporary files or dirs.
##
sub cleanupFiles {
  my ($self) = assertNumArgs(1, @_);
  foreach my $file ($self->getCleanupFiles()) {
    runCommand($self->{hostname}, "sudo rm -rf $file");
  }
}

###############################################################################
# Register code to clean up a machine after use. A cleanup step is a subroutine
# that takes one argument, the RemoteMachine to run on.
##
sub addCleanupStep {
  my ($self, $step) = assertNumArgs(2, @_);
  unshift(@{$self->{_cleanupSteps}}, $step);
}

###############################################################################
# Run the list of cleanup steps in reverse order of registration.
##
sub runCleanupSteps {
  my ($self) = assertNumArgs(1, @_);
  map { $_->($self) } @{$self->{_cleanupSteps}};
}

###############################################################################
# Return debugging information on the network state.
#
# @return string containing what commands were run and what the results were.
##
sub getNetworkState {
  my ($self) = assertNumArgs(1, @_);
  return getHostNetworkState($self->getName());
}

###############################################################################
# Read the contents of a file
#
# @param path  Path name of the file
#
# @return the contents of the file
##
sub cat {
  my ($self, $path) = assertNumArgs(2, @_);
  $self->runSystemCmd("cat $path");
  return $self->getStdout();
}

###############################################################################
# Read the contents of a file, and chomp the newline off of the output.
#
# @param path  Path name of the file
#
# @return the contents of the file (sans \n)
##
sub catAndChomp {
  my ($self, $path) = assertNumArgs(2, @_);
  my $stdout = $self->cat($path);
  chomp($stdout);
  return $stdout;
}

###############################################################################
# Get the system page size
#
# @return the page size
##
sub getPageSize {
  my ($self) = assertNumArgs(1, @_);
  $self->runSystemCmd("getconf PAGESIZE");
  my $stdout = $self->getStdout();
  chomp($stdout);
  return $stdout;
}

###############################################################################
# Run /bin/dd.  Takes arguments as key-value pairs.
#
# @oparam bs     Block size (passed using bs= to dd)
# @oparam conv   Conversion options (passed using conv= to dd)
# @oparam count  Block count (passed using count= to dd)
# @oparam if     Input filename (passed using if= to dd)
# @oparam of     Output filename (passed using of= to dd)
# @oparam oflag  Output flags (passed using oflag= to dd)
# @oparam seek   The first block number to write on the device (passed using
#                seek= to dd)
# @oparam skip   The first block number to read from the device (passed using
#                skip= to dd)
##
sub dd {
  my ($self, %params) = assertMinArgs(1, @_);
  my $parameters = join(" ", map { "$_=$params{$_}" } keys(%params));
  $self->runSystemCmd("sudo dd $parameters");
}

###############################################################################
# Turn off console blanking, so we can see stack traces even if the
# virtual machine gets seriously wedged by a kernel module we're about
# to load.  Assume console is tty1.
##
sub disableConsoleBlanking {
  my ($self) = assertNumArgs(1, @_);
  return $self->runSystemCmd("env TERM=linux setterm -blank 0"
                             . " | sudo dd of=/dev/tty1");
}

###############################################################################
# Remove a device mapper device.
#
# @param deviceName  the name of the device
##
sub dmsetupRemove {
  my ($self, $deviceName) = assertNumArgs(2, @_);
  my $removeCommand = "sudo dmsetup remove $deviceName";
  $log->debug($self->getName() . ": $removeCommand");
  my $remove = sub {
    if ($self->sendCommand($removeCommand) == 0) {
      return 1;
    }
    my $stderr = $self->getStderr();
    if ($stderr !~ m/Device or resource busy/) {
      chomp($stderr);
      confess("$removeCommand failed:  $stderr");
    }
    return 0;
  };
  my $fail = sub {
    my ($errorMsg) = assertNumArgs(1, @_);
    $self->executeCommand("sudo dmsetup info $deviceName");
    confess($errorMsg);
  };
  # A running /sbin/blkid may interfere with the dmsetup command, causing
  # it to fail with an EBUSY error.  This could happen about 1% of the
  # time.  The /sbin/blkid will finish quickly, so we just run the command
  # again.  See VDO-321.
  retryUntilTimeout($remove, "failed to remove $deviceName", 10, 0.001, $fail);
}

###############################################################################
# Flush the page cache as much as possible, attempting to force the next read
# to come from a storage device
##
sub dropCaches {
  my ($self) = assertNumArgs(1, @_);
  $self->runSystemCmd("sync;",
                      "sleep 4;",
                      "sudo sh -c 'echo 3 >/proc/sys/vm/drop_caches'");
}

###############################################################################
# Does an emergency restart.  Does not do a clean shutdown.
##
sub emergencyRestart {
  my ($self) = assertNumArgs(1, @_);
  $self->syncJournal();
  Permabit::LabUtils::emergencyRestart($self->getName());
  # Now we need to reset the RemoteMachine
  $self->resetSession();
  $self->setHungTaskWarnings();
  fixNextBootDevice($self->getName());
}

###############################################################################
# Get the lines that have been added to the specified log file.
#
# @param file      The log file to get the added lines for.
# @param position  Line number to start from (returned from getLogSize), or
#                  undef to start at the beginning of the file.
#
# @return the text added to the file
##
sub getLogAdditions {
  my ($self, $file, $position) = assertNumArgs(3, @_);
  $position ||= 0;
  $self->syncLog($file);
  $self->runSystemCmd("sudo tail -n +$position $file");
  return $self->getStdout();
}

###############################################################################
# Get the current position in the specified log file.
#
# @param  file The log file to get the size of.
#
# @return the current line number
##
sub getLogSize {
  my ($self, $file) = assertNumArgs(2, @_);
  # Capture the current size of the file
  my $wc = "wc -l $file";
  $self->runSystemCmd("sudo $wc");
  my $stdout = $self->getStdout();
  # stdout should look like "27405 /var/log/kern.log" (replace 27405 with the
  # actual number of lines in the file)
  if ($stdout !~ m"^(\d+)\s+\Q$file\E\n") {
    chomp($stdout);
    confess("Unexpected stdout from '$wc': '$stdout'");
  }
  return 0 + $1;
}

###############################################################################
# Initialize the saved log cursor and kernel log cursor
##
sub initJournalCursors {
  my ($self) = assertNumArgs(1, @_);
  $self->{_journalCursor} = $self->getJournalCursor();
  $self->{_journalKernelCursor} = $self->getKernelJournalCursor();
}

###############################################################################
# Send a command and log stderr if it returns non-zero status
#
# @param command the command string to send
##
sub checkedSendCommand {
  my ($self, $command) = assertNumArgs(2, @_);
  $log->debug("$self->{hostname}: $command");
  my $result = $self->sendCommand($command);
  if ($result != 0) {
    $self->_logOutput("$self->{hostname}: stderr", $self->getStderr());
  }
}

###############################################################################
# Get the current log cursor or kernel log cursor
#
# @oparam kernel  if true, get the current kernel cursor
#
# @return a string representation of the current log cursor
##
sub getJournalCursor {
  my ($self, $kernel) = assertMinMaxArgs([0], 1, 2, @_);
  my $cmd = "sudo journalctl -n 1 --show-cursor";
  if ($kernel) {
    $cmd .= " -k";
  }
  $self->checkedSendCommand($cmd);
  my $stdout = $self->getStdout();
  my $cursor;
  if ($stdout =~ m/^-- cursor: (.*)$/m)  {
    $cursor = $1;
  }
  $log->debug("New cursor " . ($cursor // "undefined"));
  return $cursor;
}

###############################################################################
# Get the current kernel log cursor
#
# @return a string representation of the current kernel log cursor
##
sub getKernelJournalCursor {
  my ($self) = assertNumArgs(1, @_);
  return $self->getJournalCursor(1);
}

###############################################################################
# Get journal log messages after a given cursor. If the cursor is
# undefined for some reason, get journal log messages since this
# RemoteMachine was instantiated.
#
# @param  cursor  The starting cursor
# @oparam kernel true to get kernel messages
#
# @return a string containing all log lines newer than the cursor
##
sub getJournalSince {
  my ($self, $cursor, $kernel) = assertMinMaxArgs([0], 2, 3, @_);
  my $journalCmd = "sudo journalctl -o short-monotonic";
  if (defined($cursor)) {
    $journalCmd .= " --after-cursor '$cursor'";
  } else {
    $journalCmd .= " --since='\@$self->{_journalStartTime}'";
  }
  if ($kernel) {
    $journalCmd .= " -k";
  }
  $self->syncJournal();
  $self->checkedSendCommand($journalCmd);
  return $self->getStdout();
}

###############################################################################
# Get kernel log messags after a given cursor. If the cursor is
# undefined for some reason, get journal log messages since this
# RemoteMachine was instantiated.
#
# @param  cursor  The starting cursor
#
# @return a string containing all kernel log lines newer than the cursor
##
sub getKernelJournalSince {
  my ($self, $cursor) = assertNumArgs(2, @_);
  return $self->getJournalSince($cursor, 1);
}

###############################################################################
# Get new messages since the last saved cursor and update the saved
# cursor. If the saved cursor is undefined for some reason, get
# journal log messages since this RemoteMachine was instantiated.
#
# @oparam  kernel if true return kernel messages else user messages
#
# @return  a string containing journal log messages since cursor
##
sub getNewJournal {
  my ($self, $kernel) = assertMinMaxArgs([0], 1, 2, @_);
  my $cmd = "sudo journalctl -o short-monotonic --show-cursor";
  my $cursor
    = $kernel ? $self->{_journalKernelCursor} : $self->{_journalCursor};
  if (defined($cursor)) {
    $cmd .= " --after-cursor '$cursor'";
  } else {
    $cmd .= " --since '\@$self->{_journalStartTime}'";
  }
  if ($kernel) {
    $cmd .= " -k";
  }
  $self->syncJournal();
  $self->checkedSendCommand($cmd);
  my $stdout = $self->getStdout();
  $stdout =~ m/^-- cursor: (.*)$/m;
  $cursor = $1;
  $log->debug("New cursor " . ($cursor // "undefined"));
  # Update the cursor if possible
  if (defined($cursor)) {
    if ($kernel) {
      $self->{_journalKernelCursor} = $cursor;
    } else {
      $self->{_journalCursor} = $cursor;
    }
  }
  return $stdout;
}

###############################################################################
# Get new kernel messages since the last saved cursor and update the
# saved cursor. If the cursor is undefined for some reason, get
# journal log messages since this RemoteMachine was instantiated.
#
# @return  a string containing journal log messages since cursor
##
sub getNewKernelJournal {
  my ($self) = assertNumArgs(1, @_);
  return $self->getNewJournal(1);
}

###############################################################################
# Search the journal log for a pattern after a given cursor. If the
# cursor is undefined, get journal log messages since this
# RemoteMachine was instantiated.
#
# @param  cursor  The starting point for the search
# @param  pattern The pattern regular expression
# @oparam kernel  True to search kernel messages
#
# @return true if the pattern is found
##
sub searchJournalSince {
  my ($self, $cursor, $pattern, $kernel) = assertMinMaxArgs([0], 3, 4, @_);
  $self->syncJournal();
  return $self->_searchJournalNosync($cursor, $pattern, $kernel);
}

###############################################################################
# Search the kernel journal log for a pattern after a given cursor. If
# the cursor is undefined, get journal log messages since this
# RemoteMachine was instantiated.
#
# @param  cursor  The starting point for the search
# @param  pattern The pattern regular expression
#
# @return true if the pattern is found
##
sub searchKernelJournalSince {
  my ($self, $cursor, $pattern) = assertNumArgs(3, @_);
  $self->syncJournal();
  return $self->_searchJournalNosync($cursor, $pattern, 1);
}

###############################################################################
# Search the journal log for a pattern without sync'ing first.
#
# @param  cursor  The cursor cursor at which to start searching, if
#                 undefined, start at $self->{_journalStartTime}
# @param  pattern The pattern to search for
# @oparam kernel  If true, search for kernel messages
#
# @return true if the pattern was found, false otherwise
##
sub _searchJournalNosync {
  my ($self, $cursor, $pattern, $kernel) = assertMinMaxArgs([0], 3, 4, @_);

  my $cmd = "sudo journalctl -o short-monotonic";
  if (defined($cursor)) {
    $cmd .= " --after-cursor '$cursor'";
  } else {
    $cmd .= " --since='\@$self->{_journalStartTime}'";
  }
  if (defined($kernel)) {
    $cmd .= " -k";
  }
  $self->checkedSendCommand($cmd);
  my $stdout = $self->getStdout();
  if ($stdout =~ m/$pattern/m) {
    return 1;
  } else {
    return 0;
  }
}

###############################################################################
# Sync the journal log (if the --sync option exists) and wait for a
# log marker to appear so that all logging to this point is saved to
# the backing storage.
#
##
sub syncJournal {
  my ($self) = assertNumArgs(1, @_);
  my $marker = "Sync Marker " . makeRandomToken(10);
  $self->setProcFile($marker, "/sys/permatest/printk");
  $self->checkedSendCommand("sudo journalctl --sync");
  my $findMarker = sub {
    $self->_searchJournalNosync(undef, $marker, 1);
  };
  retryUntilTimeout($findMarker, "syncJournal failure", 2 * $MINUTE, 0.1);
}

###############################################################################
# Search the log for a pattern starting with the marker that is set by
# getLogSize() or from beginning of the log, without syncing the
# log first. Return true if the pattern is found, return false otherwise.
#
# @param  file      The log file to search.
# @param  position  Position number to start the search (returned from
#                   getLogSize), or undef to start at the beginning
#                   of the file.
# @param  string    The string to search for.
#
# @return true if the string is found
##
sub grepLog {
  my ($self, $file, $position, $string) = assertNumArgs(4, @_);
  $position ||= 0;
  my $cmd = "sudo tail -n +$position $file | fgrep -q '$string'";
  if ($self->sendCommand($cmd) == 0) {
    return 1;
  }

  # Didn't find it. Maybe the log has rolled?
  if ($self->sendCommand("sudo wc -l $file") != 0) {
    # Couldn't wc -l the log; something is wrong.
    confess("Failed while running wc -l on $self->{hostname}:\n"
             . $self->_getCmdOutput());
  }

  $self->getStdout() =~ m/^(\d+)/;
  if ($position <= (0 + $1)) {
    # Hasn't rolled, legitimately not found.
    return 0;
  }

  # Probably rolled.
  $cmd = "sudo cat $file.1 $file | tail -n +$position | fgrep -q '$string'";
  return ($self->sendCommand($cmd) == 0);
}

###############################################################################
# Get the lines that have been added to /var/log/kern.log
#
# @param position  Line number to start from (returned from getKernLogSize), or
#                  undef to start at the beginning of the file.
#
# @return the text added to the file
##
sub getKernLogAdditions {
  my ($self, $position) = assertNumArgs(2, @_);
  return $self->getLogAdditions($KERN_LOG, $position);
}

###############################################################################
# Get the current position in the file /var/log/kern.log
#
# @return the current line number
##
sub getKernLogSize {
  my ($self) = assertNumArgs(1, @_);
  return $self->getLogSize($KERN_LOG);
}

###############################################################################
# Search the kernel log for a pattern starting with the marker that is set by
# getKernLogSize() or from beginning of kernel log, without syncing the kernel
# log first. Return true if the pattern is found, return false otherwise.
#
# @param  position  Position number to start the search (returned from
#                   getKernLogSize), or undef to start at the beginning
#                   of the file.
# @param  string    The string to search for
#
# @return true if the string is found
##
sub grepKernLog {
  my ($self, $position, $string) = assertNumArgs(3, @_);
  return $self->grepLog($KERN_LOG, $position, $string);
}

###############################################################################
# Rotate the system logs immediately.  This is done by tests that tend to
# log a lot of messages to /var/log/kern.log.  Forcing the log rotation
# allows the machine to immediately pass checkServer, and therefore the
# test can release the machine.
##
sub logRotate {
  my ($self) = assertNumArgs(1, @_);
  # cron runs logrotate hourly, but logrotate is not prepared to deal with 2
  # simultaneous logrotate commands.  If we get an error, just hope that the
  # other logrotate worked!
  eval { $self->runSystemCmd("sudo logrotate /etc/logrotate.conf"); };
  if (my $error = $EVAL_ERROR) {
    $log->warn("logrotate failed: $error");
  }
}

###############################################################################
# Turn the machine's power off, shutting down cleanly if possible.
##
sub powerOff {
  my ($self) = assertNumArgs(1, @_);
  Permabit::LabUtils::powerOff($self->getName());
  $self->close();
}

###############################################################################
# Turn the machine's power on.
##
sub powerOn {
  my ($self) = assertNumArgs(1, @_);
  Permabit::LabUtils::powerOn($self->getName());
  # Now we need to reset the RemoteMachine.
  $self->resetSession();
  $self->setHungTaskWarnings();
  fixNextBootDevice($self->getName());
}

###############################################################################
# Does a clean restart.
##
sub restart {
  my ($self) = assertNumArgs(1, @_);
  rebootMachines($self->getName());
  # Now we need to reset the RemoteMachine.
  $self->resetSession();
  $self->setHungTaskWarnings();
  fixNextBootDevice($self->getName());
}

###############################################################################
# Search a log file for a pattern starting with the marker that is set by
# getLogSize() or from beginning of log file. Return true if the pattern
# is found, return false otherwise.
#
# @param file      The log file to search.
# @param position  Position number to start the search (returned from
#                  getLogSize), or undef to start at the beginning
#                  of the file.
# @param string    The string to search for
#
# @return true if the string is found
##
sub searchLog {
  my ($self, $file, $position, $string) = assertNumArgs(4, @_);
  $self->syncLog($file);
  return $self->grepLog($file, $position, $string);
}

###############################################################################
# Search the kernel log for a pattern starting with the marker that is set by
# getKernLogSize() or from beginning of kernel log. Return true if the pattern
# is found, return false otherwise.
#
# @param position  Position number to start the search (returned from
#                  getKernLogSize), or undef to start at the beginning
#                  of the file.
# @param string    The string to search for
#
# @return true if the string is found
##
sub searchKernLog {
  my ($self, $position, $string) = assertNumArgs(3, @_);
  return $self->searchLog($KERN_LOG, $position, $string);
}

###############################################################################
# Write a file in the /proc filesystem
#
# @param  contents  Text to be written
# @param  path      Path name
# @oparam ifExists  True to write to the file only if it exists, or false to
#                   always write to the file
##
sub setProcFile {
  my %OPTIONS = (ifExists => 0);
  my ($self, $contents, $path, $args ) = assertOptionalArgs(3, \%OPTIONS, @_);
  my $command = "echo $contents | sudo tee -a $path";
  if ($args->{ifExists}) {
    $self->runSystemCmd("if test -f $path; then $command; else true; fi");
  } else {
    $self->runSystemCmd($command);
  }
}

###############################################################################
# Set the number of hung task warnings to be reported
#
# @oparam count  The number of hung task warnings to report.  If not specified,
#                the hungTaskWarnings property will be used.
##
sub setHungTaskWarnings {
  my ($self, $count) = assertMinMaxArgs([undef], 1, 2, @_);
  $count //= $self->{hungTaskWarnings};
  # Some systems are not configured to have hung task warnings.
  # So we allow this write to fail.
  $self->setProcFile($count, "/proc/sys/kernel/hung_task_warnings",
                     ifExists => 1);
}

###############################################################################
# Set CPU affinity (as a list of CPU ids, e.g., "0-3,5,7") for a
# specified interrupt number.
#
# This may have no effect if the "irqbalance" daemon is running.
#
# @param irq    The interrupt number to adjust
# @param cores  The list of cores on which the interrupt can be serviced
##
sub setIRQAffinity {
  my ($self, $irq, $cores) = assertNumArgs(3, @_);
  $self->setProcFile($cores, "/proc/irq/$irq/smp_affinity_list");
}

###############################################################################
# Sync the log file.
#
# @param file  The log file to sync
##
sub syncLog {
  my ($self, $file) = assertNumArgs(2, @_);
  if ($file !~ m"^/var/log/") {
    # There is no need to perform the sync operation, because this is a log
    # that is not managed using the system logger.  In particular, tests can
    # arrive here when reading the vdoManager log file.
    return;
  }
  my $position = $self->getLogSize($file) + 1;
  my $marker = "Sync Marker " . makeRandomToken(10);
  if ($file eq $KERN_LOG) {
    $self->setProcFile($marker, "/sys/permatest/printk");
  } elsif ($file eq $DAEMON_LOG) {
    $self->runSystemCmd("logger -p daemon.error $marker");
  } elsif ($file eq $SYS_LOG) {
    $self->runSystemCmd("logger -p syslog.error $marker");
  } elsif ($file eq $USER_LOG) {
    $self->runSystemCmd("logger -p user.error $marker");
  } else {
    my @logList = ($KERN_LOG, $DAEMON_LOG, $SYS_LOG, $USER_LOG);
    croak("$file is not a supported /var/log file name: @logList");
  }
  my $waitForMarker = sub { return $self->grepLog($file, $position, $marker); };
  retryUntilTimeout($waitForMarker, "syncLog failure", 2 * $MINUTE, 0.1);
}

###############################################################################
# Sync the kernel log.
##
sub syncKernLog {
  my ($self) = assertNumArgs(1, @_);
  $self->syncLog($KERN_LOG);
  # Bonus: sync journald log.
  $self->syncJournal();
}

###############################################################################
# Wait for any active disk self-tests to complete
#
# @croaks if we can't parse the output from smartctl.
##
sub waitForDiskSelfTests {
  my ($self) = assertNumArgs(1, @_);
  my $cmd = "awk '/ [hs]d[a-z]\$/ { print \$NF; }' /proc/partitions";
  $self->runSystemCmd($cmd);
  foreach my $dev (split (/[ \n]+/, $self->getStdout())) {
    $self->runSystemCmd("sudo smartctl -i /dev/$dev");
    my $smartInfo = $self->getStdout();
    if ($smartInfo !~ /ATA Version/) {
      $log->info("$dev appears not to be ATA, skipping self-test check");
      next;
    } elsif ($smartInfo =~ /Device does not support SMART/) {
      $log->warn("$dev doesn't support SMART -- skipping check");
      next;
    } elsif ($smartInfo =~ /Device supports SMART and is Enabled/) {
      $log->debug("checking device $dev for running selftest");
    } elsif ($smartInfo =~ /SMART support is: Enabled/) {
      $log->debug("checking device $dev for running selftest");
    } else {
      croak("can't determine if $dev supports SMART:\n$smartInfo");
    }
    while (1) {
      # See "ataprint.cpp" in smartmontools source code for more details on the
      # various output messages.
      # Specify the selftest log as that is apparently the only way to tell
      # if self-test logging is supported.
      $self->runSystemCmd("sudo smartctl -c -l selftest /dev/$dev");
      my $smartStatus = $self->getStdout();
      if ($smartStatus =~ /Self-test routine in progress/) {
        # Wait and try again.  For some (not all) disks, we could abort the
        # test with "smartctl -X", but if our nightly testing does that too
        # much, we'll never get the tests run.
        $log->info("disk self-test running on $dev, sleeping");
        sleep(30);
        next;
      }
      # Check for acceptable scenarios.  If there is no self-test log it
      # better be because self-test itself isn't supported.
      if ((($smartStatus =~ /Self-test Log not supported/)
            && ($smartStatus =~ /No Self-test supported/))
          || ($smartStatus =~ /The previous self-test routine completed/)
          || ($smartStatus =~ /The self-test routine was aborted by/)
          || ($smartStatus =~ /The self-test routine was interrupted/)
          || ($smartStatus =~ /The previous self-test completed having/)
          || ($smartStatus =~ /A fatal error or unknown test error/)) {
        # Either there's no self-test log or we have results we expect.
        # If the former we assume everything is fine.
        # If the latter, for the last two errors, there's probably something
        # wrong with the drive. Here is probably not the right place to deal
        # with such failures here though we could log a warning/error.
        last;
      }
      # No known message matched.
      croak("unexpected output from smartctl: $smartStatus");
    }
  }
}

###############################################################################
# Expand a CPU-list specification read from a
# /sys/devices/system/node/node*/cpulist special file.
#
# @param cpuList    The cpu-list string
#
# @return  a sorted list of numbers
##
sub _expandCPUList {
  my ($cpuList) = assertNumArgs(1, @_);
  # CPU numbers within a node are probably consecutive, so no need to
  # check for a comma.
  if ($cpuList =~ m/^\d+$/) {
    return ( 0 + $cpuList );
  }
  if ($cpuList =~ m/^(\d+)-(\d+)$/) {
    my $min = 0 + $1;
    my $max = 0 + $2;
    return $min ... $max;
  }
  croak("unrecognized cpu-list format: '$cpuList'");
}

###############################################################################
# Produce a hash indicating which cores are on which nodes.
#
# @return  an arrayref, indexed by node number, containing arrayrefs of
#          CPU core numbers
##
sub getNUMAMap {
  my ($self) = assertNumArgs(1, @_);
  $self->runSystemCmd("cd /sys/devices/system/node && egrep . node*/cpulist");
  my $output = $self->getStdout();
  chomp($output);
  my @lines = split(/\n/, $output);
  my %map = map {
    m|^node(\d+)/cpulist:([0-9,-]+)$|;
    my $node = 0 + $1;
    my @cores = _expandCPUList($2);
    $node => \@cores;
  } @lines;
  my @nodes = sort(keys(%map));
  my @coreList = @map{@nodes};
  return \@coreList;
}

###############################################################################
# Find IRQ numbers associated with a particular device or driver.
#
# Scans /proc/interrupts for the named interrupt, and extracts the IRQ
# number(s) associated with it.
#
# @param interruptName  The device/driver name to look for
#
# @return  a list of numbers
##
sub getInterruptsByName {
  my ($self, $interruptName) = assertNumArgs(2, @_);
  $self->runSystemCmd("grep $interruptName /proc/interrupts");
  my $output = $self->getStdout();
  chomp($output);
  my @lines = split('\n', $output);
  my @irqs = map { s/^ +//; s/:.*$//; $_; } @lines;
  return @irqs;
}

###############################################################################
# Check if a given path exists
#
# @param path  Path name
#
# @return true if path exists
##
sub pathExists {
  my ($self, $path) = assertNumArgs(2, @_);
  return $self->executeCommand("test -e $path") == 0;
}

###############################################################################
# Test if the machine is virtualized
##
sub isVirtual {
  my ($self) = assertNumArgs(1, @_);
  if (!defined($self->{_isVirtual})) {
    $self->{_isVirtual} = isVirtualMachine($self->getName());
  }
  return $self->{_isVirtual};
}

###############################################################################
# Overload default stringification to print our hostname
##
sub as_string {
  my $self = shift;
  return "RemoteMachine($self->{hostname})";
}

1;
