##
# Perl module that runs a series of programs in a bash shell.
#
# This module encapsulates the open3() function call (see L<IPC::Open3>) and
# its associated filehandles.  This makes it easy to maintain persistent bash
# sessions, within a same perl script.
#
# The remote shell session is kept open for the life of the object; this avoids
# the overhead of repeatedly opening remote shells via multiple bash calls.
# This persistence is particularly useful if you are using ssh for your remote
# shell invocation; it helps you overcome the high ssh startup time.
#
# The remote shell session should be over an SSH TCP connection.  We look for
# the remote sshd process that is the parent of the remote shell.  We need the
# ID of the remote sshd process to shutdown cleanly.
#
# There is nothing inherently bash-ish about Permabit::BashSession.  It doesn't
# even know anything about bash, as a matter of fact.  It will work with any
# interactive shell that supports these features:
#
#      $? as the command exit status (this rules out /bin/csh)
#
#      >&2 to redirect stdout onto stderr (in other words, "echo foo >&2"
#          writes "foo\n" into stdout)
#
# $Id$
##
package Permabit::BashSession;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English qw(-no_match_vars);
use Errno qw(EINTR);
use FileHandle;
use IPC::Open3;
use Log::Log4perl;
use Permabit::Assertions qw(assertDefined assertNumArgs);
use Permabit::Exception qw(SSH);
use Permabit::LabUtils qw(getSystemUptime);
use Permabit::SystemUtils qw(runQuietCommand);
use Time::HiRes qw(sleep time);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

##########################################################################
# Create a Permabit::BashSession
#
# @param shellCommand  The command to run the shell, which can include an ssh
#                      invocation.
# @param hostname      The name of the remote host.
#
# @return the Permabit::BashSession
##
sub new {
  my ($invocant, $shellCommand, $hostname) = assertNumArgs(3, @_);
  my $class = ref($invocant) || $invocant;
  my $self = bless({ _hostname => $hostname }, $class);

  # so we can use more than one of these objects
  local (*IN,*OUT,*ERR);
  $self->{_pid} = open3(\*IN, \*OUT, \*ERR, $shellCommand);
  if ($self->{_pid} == 0) {
    confess("$ERRNO");
  }
  $self->{stdin}  = *IN;
  $self->{stdout} = *OUT;
  $self->{stderr} = *ERR;

  # Set to autoflush.
  select(*IN);
  $OUTPUT_AUTOFLUSH = 1;
  select(STDOUT);

  # Set the umask to 002
  $self->send("umask 02");

  # Record the parent of the remote bash process
  $self->send('cat /proc/$$/stat');
  $self->{_remotePid} = (split(" ", $self->{commandStdout}, 5))[3];
  assertDefined($self->{_remotePid});

  # Record the boot time of the remote machine.  Fetch the uptime before the
  # clock time so that we record a time NOT before the actual boot time.
  my $remoteUptime = getSystemUptime($self->{_hostname});
  $self->{_bootTime} = time() - $remoteUptime;

  return $self;
}

##########################################################################
# Send a command to the bash
#
# @param cmd  The bash command line
#
# @return the end-of-text marker string
##
sub _tx {
  my ($self, $cmd) = assertNumArgs(2, @_);
  my $eot = "_EoT_" . rand() . "_";
  my $fh = $self->{stdin};

  print $fh "$cmd\n";
  print $fh "echo $eot errno=\$?\n";
  print $fh "echo $eot >&2\n";
  return $eot;
}

##########################################################################
# Read command output from the bash
#
# @param eot  The end-of-text marker string
#
# @return a list of stdout text, stderr text, and the exit status
#
# @croaks if we lose the SSH connection to the remote shell
##
sub _rx {
  my ($self, $eot) = assertNumArgs(2, @_);
  my $status = "";
  # In the following arrays, element 0 is for stdout, element 1 for stderr.
  my @handles = ($self->{stdout}, $self->{stderr});
  # For matching the end-of-text marker in each output stream.
  my @regexps = (qr/\Q$eot\E errno=(\d+)\n/, qr/\Q$eot\E\n/);
  # For buffering any text following the last newline read from each stream.
  my @tails = ("", "");
  # For buffering complete lines of text that did not match the EOT marker.
  my @outputs = ("", "");

  # A bitvector of the file descriptor numbers that select should poll.
  my $activeFDs = "";
  vec($activeFDs, fileno($self->{stdout}), 1) = 1;
  vec($activeFDs, fileno($self->{stderr}), 1) = 1;

  # This eval lets us compose a better error message
  eval {
    # we collect output until we have read the EOT marker on both streams
    # (double-braces so "next" will actually work like you'd expect it to)
    do {{
      # Wait for command output to become available on either stream.
      my $readyFDs = $activeFDs;
      if (select($readyFDs, undef, undef, undef) < 0) {
        if ($ERRNO == EINTR) {
          next;
        }
        confess("select error $ERRNO");
      }

      foreach my $streamIndex (0, 1) {
        my $fd = $handles[$streamIndex];
        if (!vec($readyFDs, fileno($fd), 1)) {
          next;
        }

        # Read as much output as is available on the stream, appending to
        # the last unterminated line.
        my $tail = \$tails[$streamIndex];
        my $offset = length($$tail);
        my $bytesRead = sysread($fd, $$tail, 65536, $offset);
        if (not $bytesRead) {
          _handleReadResult($bytesRead,
                            ($streamIndex == 0) ? "stdout" : "stderr");
          # Read was interrupted, so skip this stream for now.
          next;
        }

        my $newTailOffset = rindex($$tail, "\n") + 1;
        if ($newTailOffset == 0) {
          # Still haven't read a newline, so keep on reading and accumulating.
          next;
        }

        if ($$tail !~ /$regexps[$streamIndex]/p) {
          # The EoT marker was not found preceding the last newline, so
          # everything up to it is output to collect.
          $outputs[$streamIndex] .= substr($$tail, 0, $newTailOffset, "");
          next;
        }

        # We found the EOT marker for this stream. If it's from stdout, save
        # the status code it contained.
        if ($streamIndex == 0) {
          $status = $1;
        }

        # It should be impossible for there to be anything after the EoT
        # marker, but sometimes there's a forked process also writing to
        # stdout, as happened with vdomonitor in VDO-4820 et al.
        if (length(${^POSTMATCH}) > 0) {
          $log->warn("flushing data past EoT marker: '${^POSTMATCH}'");
        }

        # Transfer any data preceding the EoT marker to the output buffer.
        $outputs[$streamIndex] .= ${^PREMATCH};

        $$tail = "";
        vec($activeFDs, fileno($fd), 1) = 0;
      }
      # A cheap way to check whether either bit is still set in the vector.
    }} while (unpack("%32b*", $activeFDs));
  };
  if (my $eval_error = $EVAL_ERROR) {
    # Sometimes we seem to hang in _rx waiting for a command that failed (as
    # in VDO-4463). This very verbose logging is to learn more the next time.
    $log->warn("stdout read: $outputs[0]");
    if ($tails[0] ne "") {
      $log->warn("stdout line buffer: $tails[0]");
    } elsif (vec($activeFDs, fileno($self->{stdout}), 1) == 0) {
      $log->warn("stdout read EOT marker (errno=$status)");
    }

    $log->warn("stderr read: $outputs[1]");
    if ($tails[1] ne "") {
      $log->warn("stderr line buffer: $tails[1]");
    } elsif (vec($activeFDs, fileno($self->{stderr}), 1) == 0) {
      $log->warn("stderr read EOT marker");
    }

    if ($eval_error->isa("Permabit::Exception::Signal")) {
      $self->{_signaled} = 1;
    }
    die($eval_error);
  }
  return ($outputs[0], $outputs[1], $status);
}

##########################################################################
# Handle the return value from a sysread call.
#
# @param result  The result to check, which should be zero for EOF and
#                undef for any error
# @param handle  "stdout" or "stderr"
#
# @croaks on EOF or if we lose the SSH connection to the remote shell
##
sub _handleReadResult {
  my ($result, $handle) = assertNumArgs(2, @_);
  if (defined($result)) {
    if ($result) {
      # True (positive) means data was read.
      return;
    }
    # False (0) means we are at end of file.
    die(Permabit::Exception::SSH->new("eof read error from $handle"));
  }

  if ($ERRNO != EINTR) {
    # Undefined and $ERRNO != EINTR means we got an error.
    die(Permabit::Exception::SSH->new("read error: $ERRNO from $handle"));
  }
  # Undefined and $ERRNO == EINTR means we should try again.
}

##########################################################################
# Flush the data from a file handle
#
# @param handle  "stdout" or "stderr"
#
# @croaks if we lose the SSH connection to the remote shell
##
sub rxflush {
  my ($self, $handle) = assertNumArgs(2, @_);
  if ($self->{_signaled}) {
    die("BashSession previously interrupted by a signal");
  }
  my $fh = $self->{$handle};
  my $rin = "";
  vec($rin, fileno($fh), 1) = 1;
  # while there is input available
  while (select(my $rout = $rin, undef, undef, 0) > 0) {
    # read the data and throw it away
    my $buffer;
    _handleReadResult(sysread($fh, $buffer, 65536), $handle);
  }
}

##########################################################################
# Execute a command string to be on the bash session.  All shell escapes,
# command line terminators, pipes, redirectors, etc. are legal and should work,
# though you of course will have to escape special characters that have meaning
# to Perl.
#
# @param command  The command string
#
# @return In a scalar context, this method returns the return code produced by
#         the command string.  In an array context, this method returns a hash
#         containing the return code as well as the full text of the command
#         string's output from the STDOUT and STDERR file handles.  The hash
#         keys are "stdout", "stderr", and "errno".
#
# @croaks if we lose the SSH connection to the remote shell
##
sub send {
  my ($self, $command) = assertNumArgs(2, @_);

  # send the command
  $self->rxflush("stdout");
  $self->rxflush("stderr");
  my $tag = $self->_tx($command);
  my ($stdout, $stderr, $errno) = $self->_rx($tag);

  $self->{commandStdout} = $stdout;
  $self->{commandStderr} = $stderr;
  $self->{commandStatus} = $errno;

  if (wantarray) {
    return (
            errno  => $self->{commandStatus},
            stdout => $self->{commandStdout},
            stderr => $self->{commandStderr}
           );
  } else {
    return $self->{commandStatus};
  }
}

##########################################################################
# Returns the full STDOUT text generated from the last send() command string.
#
# @return the full stdout text
##
sub stdout {
  my ($self) = assertNumArgs(1, @_);
  return $self->{commandStdout};
}

##########################################################################
# Returns the full STDERR text generated from the last send() command string.
#
# @return the full stderr text
##
sub stderr {
  my ($self) = assertNumArgs(1, @_);
  return $self->{commandStderr};
}

##########################################################################
# Returns the exit status generated from the last send() command string.
#
# @return the exit status
##
sub errno {
  my ($self) = assertNumArgs(1, @_);
  return $self->{commandStatus};
}

##########################################################################
# Kill the remote processes.  This is necessary so that they do not tie up
# resources that our shutdown code needs to clean up.  Then kill the child
# process and reap it.  This is necessary to prevent lots of defunct processes
# from accumulating.
##
sub close {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{_pid} <= 0) {
    return;
  }
  # Fetch the boot time of the remote machine.  Fetch the clock time before the
  # uptime so that we record a time NOT after the actual boot time.
  my $now = time();
  my $bootTime = $now - getSystemUptime($self->{_hostname});
  if (defined($self->{_bootTime}) && ($bootTime <= $self->{_bootTime})) {
    # We haven't seen the machine reboot, so kill the remote sshd and all its
    # children.
    my @parents = ($self->{_remotePid});
    my @pids;
    while (my $pid = shift(@parents)) {
      push(@pids, $pid);
      my $result = runQuietCommand($self->{_hostname},
                                   "sudo find /proc -maxdepth 2 -name status"
                                   . " -exec grep -q '^PPid:\t$pid\$' {} \\;"
                                   . " -print");
      if ($result->{stdout}) {
        push(@parents, $result->{stdout} =~ m"/(\d+)/"g);
      }
    }
    runQuietCommand($self->{_hostname}, "sudo kill @pids");
  }
  # Kill and reap the ssh process.
  kill("TERM", $self->{_pid});
  sleep(0.25);
  if (kill(0, $self->{_pid}) > 0) {
    kill("KILL", $self->{_pid});
  }
  waitpid($self->{_pid}, 0);
  $self->{_pid} = 0;
}

##########################################################################
##
sub DESTROY {
  my ($self) = @_;
  # Preserve EVAL_ERROR so any nested eval{}s won't clear the exception
  # that may have caused this destructor to be called.
  local $EVAL_ERROR;
  $self->close();
}

1;
