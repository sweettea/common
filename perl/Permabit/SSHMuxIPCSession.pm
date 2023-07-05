##
# C<Permabit::SSHMuxIPCSession> tries to behave somewhere in between
# C<IPC::Session> and C<Permabit::FakeIPCSession>.  We keep a single
# ssh session up for separation of debug info from the commands we
# want to invoke remotely; each command is invoked in a separate
# (remote) shell process, requiring that file descriptors be closed at
# the end of the command (i.e., either all processes exit, or those
# sticking around, even shell processes, are no longer connected to
# the ssh-provided stdin/out/err file handles), but not requiring
# magic echo commands to be processed at the other end to help us
# delimit each process's output.
#
# Use it via C<Permabit::IPC::Remote> or C<Permabit::RemoteMachine>.
##
package Permabit::SSHMuxIPCSession;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Errno qw(EINTR);
use Carp;
use List::Util qw(min);
use Log::Log4perl;
use Permabit::Assertions qw(assertMinArgs assertNumArgs);
use Permabit::Constants qw($MINUTE $SSH_OPTIONS);
use Permabit::Utils qw(getUserName makeRandomToken);
use IPC::Open3;
use FileHandle;
use POSIX qw(:sys_wait_h :signal_h);
use String::ShellQuote qw(shell_quote);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

##########################################################################
# The default error handler for SSHMuxIPCSession, log the error provided
# and croak.
##
sub default_handler {
  $log->logcroak("An unhandled error has occured in SSHMuxIPCSession:\n@_");
}

my %properties = (
                  # @ple Error handler
                  handler     => \&default_handler,
                  # @ple The machine this server should be run on
                  hostname    => undef,
                  # @ple Timeout for connecting and running commands
                  timeout     => 10 * 365.2425 * 24 * 60 * 60, # XXX "forever"?
                  # @ple extra arguments for the ssh connection
                  sshConArgs  => '',
                  # @ple extra ssh arguments for command dispatch
                  sshRunArgs  => '',
                 );

##########################################################################
# Construct a new IPC object.
##
sub new {
  my ($self) = assertMinArgs(1, @_);
  shift;
  if (!ref($self)) {
    $self = bless {
                   %properties,
                   # Overrides previous values
                   @_,
                  }, $self;
  }
  $log->debug("returning new SSHMuxIPCSession object, "
              . "timeout=$self->{timeout}");

  # StrictHostKeyChecking causing ossbunsen machines to fail when ssh'ing to
  # localhost. Turn off as its not really needed for localhost anyways.
  if ($self->{hostname} =~ /^(localhost|127\.0\.0\.1)$/) {
      $self->{sshConArgs}
        = $self->{sshConArgs} . " -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no ";
  }  
  return $self->createIPCSession();
}

##########################################################################
# Read some data.
##
sub fetch {
  my ($self, $stream) = assertNumArgs(2, @_);
  my $bytes;
  my $ret = sysread($stream, $bytes, 10000);
  if (! $ret) {
    return undef;
  }
  return $bytes;
}

# Internal fields:
# mstdin, mstdout, mstderr: I/O for ssh multiplexing master process
# pid: ssh mux master process id
# ctlSocket: local UNIX-domain socket for ssh mux
# handler: supplied error handler
# stdout, stderr: from most recent completed remote command (not updated
#     on timeouts)
# procStatus: exit status of most recent completed remote command
# expect_eof: Are we expecting the master to exit now?  A flag for
#     drain_and_log to decide whether to invoke the error handler.

# Note the functions below have reader loops that are slightly
# different, thus not rolled up into one helper.  One waits for the
# magic word "ready" and returns without waiting to see if there's
# more; one drains the current output without waiting; one looks at a
# different set of file handles and waits to drain all output or until
# it times out.

##########################################################################
# Initiate a session to the host.
#
# Start a multiplex-master ssh process, and have the remote side tell
# us when it's ready.
#
# We run "cat" on the remote end, so that by closing stdin to the ssh
# process (including by the killing of this process without an
# opportunity for proper cleanup), we trigger the remote end to shut
# down, leading to the termination of the local ssh child process.
# So, $SSH_OPTIONS can't use -n to prevent input.
##
sub createIPCSession {
  my ($self) = assertNumArgs(1, @_);

  $log->debug("createIPCSession");
  if (!exists $self->{handler}) {
    croak("calling IPCSession on uninitialized object??");
  }

  # Socket path names are limited to a bit over 100 characters on Linux.
  # On Beaker systems, $self->{hostname} will be an FQDN.
  $self->{ctlSocket} = ('/tmp/ssh-'
                        . getUserName()
                        . '-' . makeRandomToken(10)
                        . '-' . time
                        . '-' . $PID
                        . '-' . (split(/\./, $self->{hostname}))[0]
                        );
  my ($stdin, $stdout, $stderr)
    = (FileHandle->new(), FileHandle->new(), FileHandle->new());
  my $cmd = "ssh -v $SSH_OPTIONS -M -S $self->{ctlSocket} $self->{sshConArgs}"
            . " $self->{hostname} echo ready ';' cat";
  $log->debug("starting ssh multiplexer command: $cmd");
  $self->{pid} = open3($stdin, $stdout, $stderr, $cmd);
  my $errno = $ERRNO;
  my $handler = $self->{handler};
  if (! $self->{pid}) {
    # We were unable to create the session, so note the error and dump the
    # the command so we can try and see what might be going on
    $log->fatal("Unable to start SSH: $cmd");
    &{$handler}("Unable to start SSH:\n$cmd\n$errno");
    return undef; # handler might not croak.
  }
  $log->debug("pid $self->{pid}");
  ($self->{mstdin}, $self->{mstdout}, $self->{mstderr})
    = ($stdin, $stdout, $stderr);
  # Autoflush.
  $stdout->autoflush(1);
  $stderr->autoflush(1);

  # Look for "ready" on stdout.  If someone's .<shell>rc file prints
  # that out, someday, we could switch to a randomized cookie, but I
  # doubt it'll be needed.
  my $fdvec = "";
  vec($fdvec, fileno($self->{mstdout}), 1) = 1;
  vec($fdvec, fileno($self->{mstderr}), 1) = 1;
  my $out = "";
  my $err = "";
  # Even if we're prepared to wait for some remote commands to take a
  # long time to run, session establishment shouldn't take very long.
  # SSH will time out on one TCP connection attempt in just over two
  # minutes; if DNS gives us an IPv6 address we can't actually reach
  # (sadly too common in Beaker setups), we may need to make a second
  # attempt.
  my $timeleft = min($self->{timeout}, 5 * $MINUTE);
  my $nready;
  $log->debug("waiting for remote ready indication, timeout=$timeleft");
  while ($timeleft > 0) {
    ($nready, $timeleft) = select(my $fdread = $fdvec,undef,undef,$timeleft);
    if ($nready < 0) {
      my $errno = $ERRNO;
      if ($errno == EINTR()) {
        next;
      }
      $log->info("select returned error $errno");
      return undef;
    }
    if ($nready == 0) {
      # timed out
      last;
    }
    if (vec($fdread,fileno($self->{mstderr}),1)) {
      my $bytes = $self->fetch($self->{mstderr});
      if (!defined($bytes)) {
        my $msg = "eof on stderr during setup";
        if ($out || $err) {
          $msg .= " after reading: stdout [ $out ] stderr [ $err ]";
        }
        $log->debug("eof on stderr");
        &{$handler}($msg);
        $timeleft = -1;
      } else {
        $err .= $bytes;
      }
    }

    if (vec($fdread,fileno($self->{mstdout}),1)) {
      my $bytes = $self->fetch($self->{mstdout});
      if (!defined($bytes)) {
        my $msg = "eof on stdout during setup";
        if ($out || $err) {
          $msg .= " after reading: stdout [ $out ] stderr [ $err ]";
        }
        $log->debug("eof on stdout");
        &{$handler}($msg);
        $timeleft = -1;
      } else {
        $out .= $bytes;
      }
    }
    if ($out =~ /ready/) {
      last;
    }
  }

  if ($nready == 0) {
    $log->debug("quit wait loop on timeout");
    my $msg = "timeout during setup";
    if ($out || $err) {
      $msg .= " after reading: stdout [ $out ] stderr [ $err ]";
    }
    kill('INT', $self->{pid});
    waitpid($self->{pid}, 0);
    &{$handler}($msg);
    undef $self;
  } elsif ($timeleft == -1) {
    kill('INT', $self->{pid});
    waitpid($self->{pid}, 0);
    undef $self;
  }

  # Here if we got 'ready', or failed but the handler returned.
  if (defined($self)) {
    $self->{expect_eof} = 0;
  }
  return $self;
}

##########################################################################
# Drain any pending output from the ssh master process, log it, and go
# on.  If expect_eof isn't set, and we hit eof, invoke the handler.
##
sub drain_and_log {
  my ($self) = assertNumArgs(1, @_);

  if (!exists $self->{mstdout}) {
    croak("drain_and_log with no mstdout");
  }

  my $fdvec = "";
  vec($fdvec, fileno($self->{mstdout}), 1) = 1;
  vec($fdvec, fileno($self->{mstderr}), 1) = 1;
  my ($out, $err, $nready, $timeleft) = ("", "", undef, undef);
  my $got_eof = 0;
  while ($got_eof == 0) {
    ($nready, $timeleft) = select(my $fdread = $fdvec,undef,undef,0);
    if ($nready < 0) {
      my $errno = $ERRNO;
      if ($errno == EINTR()) {
        next;
      }
      $log->info("select returned error $errno");
      return undef;
    }
    if ($nready == 0) {
      # timed out
      last;
    }
    if (vec($fdread,fileno($self->{mstderr}),1)) {
      my $bytes = $self->fetch($self->{mstderr});
      if (!defined($bytes)) {
        $got_eof++;
      } else {
        $err .= $bytes;
      }
    }
    if (vec($fdread,fileno($self->{mstdout}),1)) {
      my $bytes = $self->fetch($self->{mstdout});
      if (!defined($bytes)) {
        $got_eof++;
      } else {
        $out .= $bytes;
      }
    }
  }
  if ($got_eof) {
    my $msg = "eof from ssh mux process";
    if ($out || $err) {
      $msg .= " after reading: stdout [ $out ] stderr [ $err ]";
    }
    if (! $self->{expect_eof}) {
      &{$self->{handler}}($msg);
    }
  }
}

###############################################################################
# Send the given command.
##
sub send {
  my ($self, @rest) = assertMinArgs(1, @_);
  my $cmd = join(' ', @rest);

  $self->drain_and_log();

  my ($stdin,$stdout,$stderr)
    = (FileHandle->new(), FileHandle->new(), FileHandle->new());
  # The hostname is ignored here, when the master exists, but
  # something needs to be supplied anyways, and the real hostname is
  # best for logging purposes.
  my $sshCmd = "ssh -S $self->{ctlSocket} $self->{sshRunArgs} $self->{hostname}"
               . " " . shell_quote($cmd);
  $log->debug("starting command: $sshCmd");
  $self->block_signals(SIGCHLD);
  my $pid = open3($stdin, $stdout, $stderr, $sshCmd);
  if (!$self->{pid}) {
    my $errno = $ERRNO;
    $self->restore_signals();
    $self->{handler}->($errno);
    return wantarray() ? (stdout => '',
                          stderr => 'open3 failed',
                          errno  => $errno)
                       : $self->{pid};
  }
  # Autoflush.
  $stdout->autoflush(1);
  $stderr->autoflush(1);
  # look for "ready" on stdout; should we use a randomized cookie?
  my $fdvec = "";
  vec($fdvec, fileno($stdout), 1) = 1;
  vec($fdvec, fileno($stderr), 1) = 1;
  my ($out, $err, $timeleft, $nready, $nfds)
    = ("", "", $self->{timeout}, undef, 2);
  $log->debug("child pid $pid; waiting for completion, timeout=$timeleft");
  while ($timeleft > 0 && $nfds) {
    ($nready, $timeleft) = select(my $fdread = $fdvec,undef,undef,$timeleft);
    if ($nready < 0) {
      my $errno = $ERRNO;
      $log->info("select returned error $errno");
      if ($errno == EINTR()) {
        next;
      }
      return wantarray() ? (stdout => '',
                            stderr => 'select failed',
                            errno  => $errno)
                         : $self->{pid};
    }
    if ($nready == 0) {
      # timed out
      last;
    }
    if (vec($fdread,fileno($stderr),1)) {
      my $bytes;
      my $nRead = sysread($stderr, $bytes, 10000);
      if ($nRead == 0) {
        vec($fdvec, fileno($stderr), 1) = 0;
        $nfds--;
      } else {
        $err .= $bytes;
      }
    }
    if (vec($fdread,fileno($stdout),1)) {
      my $bytes;
      my $nRead = sysread($stdout, $bytes, 10000);
      if ($nRead == 0) {
        vec($fdvec, fileno($stdout), 1) = 0;
        $nfds--;
      } else {
        $out .= $bytes;
      }
    }
  }
  close $stdin;
  close $stdout;
  close $stderr;
  if ($nfds) {
    my $msg = "timeout during command execution";
    if ($out || $err) {
      $msg .= " after reading: stdout [ $out ] stderr [ $err ]";
    }
    # Forcefully kill the ssh connection. Unfortunately this can leave
    # the remote process still running which could also potentially cause
    # close() to hang until the command finishes. This is all less than
    # ideal...
    kill('QUIT', $pid);
    waitpid($pid, 0);
    $self->restore_signals();
    $self->{handler}->($msg);
    croak($msg);
  }

  $log->debug("closed i/o streams, waiting for proc");
  my $reapedPID  = waitpid($pid, 0);
  my $procStatus = $?;
  if ($pid != $reapedPID) {
    die("child process already reaped!"
        . " (waitpid returned $reapedPID, errno $OS_ERROR)");
  }

  $self->restore_signals();

  $self->{procStatus} = $procStatus;

  $log->debug("command result: status $procStatus stdout [ $out ]"
              . " stderr [ $err ]");

  $self->{stdout} = $out;
  $self->{stderr} = $err;
  my $result = { stdout => $out,
                 stderr => $err,
                 errno  => $procStatus,
               };

  $self->drain_and_log();

  if (wantarray()) {
    # All the info.
    return %{$result};
  } else {
    # Just process exit status, extracted from the waitpid status.
    return $self->{procStatus} >> 8;
  }
}

##########################################################################
# Uses sigprocmask(2) to block the given set of signals. It also caches
# the current signal mask so that it can be restored later with
# restore_signals.
# 
# @param signals     A list of signals to block (i.e. &POSIX::SIGCHLD)
##
sub block_signals {
  my ($self, @signals) = assertMinArgs(2, @_);
  my $oldSigSet = POSIX::SigSet->new();
  my $blockSet = POSIX::SigSet->new(@signals);
  sigprocmask(SIG_BLOCK, $blockSet, $oldSigSet)
    or croak("Could not block signals (@signals): $ERRNO");
  $self->{_oldsigset} = $oldSigSet
}

##########################################################################
# Restores the signal mask based on the set that was cached by calling
# block_signals.
##
sub restore_signals {
  my ($self) = assertNumArgs(1, @_);
  if (exists $self->{_oldsigset}) {
    sigprocmask(SIG_SETMASK, $self->{_oldsigset}, undef)
      or croak("Could not unblock signals ($self->{_oldsigset}): $ERRNO");
    delete $self->{_oldsigset};
  }
}

##########################################################################
# Get standard output.
##
sub stdout {
  my ($self) = assertNumArgs(1, @_);
  return $self->{stdout};
}

##########################################################################
# Get standard error output.
##
sub stderr {
  my ($self) = assertNumArgs(1, @_);
  return $self->{stderr};
}

##########################################################################
# Close the current session, leaving the object in a state where we
# can open another.
##
sub close {
  my ($self) = assertNumArgs(1, @_);
  $log->debug("closing session on mux pid $self->{pid} socket"
              . " $self->{ctlSocket}");
  $self->block_signals(SIGCHLD);
  # Trigger the mux-session to exit.
  close $self->{mstdin} || warn("mstdin close failed");
  $self->{expect_eof} = 1;
  # In case already exited.
  eval {
    # TODO: This will hang until all sessions are closed. It might be
    #       be better to start with a SIGINT, do a waitpid(WNOHANG) in a
    #       loop until $self->{timeout} is reached and then switch to
    #       SIGTERM which will leave processes running on the remote
    #       machine but might be the best mix of not hanging forever,
    #       yet still give us some chance to cleanup normally.
    kill('INT', $self->{pid});
    waitpid($self->{pid}, 0);
    $log->debug("ssh process $self->{pid} exited");
  };
  $self->restore_signals();
  unlink($self->{ctlSocket});
  eval {
    $self->drain_and_log();
  };
  if ($EVAL_ERROR) {
    warn("ignoring drain_and_log $EVAL_ERROR");
  }
  close $self->{mstdout} || warn("mstdout close failed");
  close $self->{mstderr} || warn("mstderr close failed");

  delete $self->{pid};
  delete $self->{ctlSocket};
  delete $self->{mstdin};
  delete $self->{mstdout};
  delete $self->{mstderr};

  $log->debug("file handles closed, socket unlinked, process killed");
}

##########################################################################
# Change the error handler to the one provided.
#
# @param handler The error handler to set the object to use.
##
sub setErrorHandler {
  my ($self, $handler) = assertNumArgs(2, @_);
  $self->{handler} = $handler;
  $log->debug("Changed the error handler, $handler");
}

##########################################################################
# Alter the timeout setting.
# 
# @param t      the number of seconds before timing out (fractional units
#               are supported).
##
sub timeout {
  # TODO setTimeout is a better name for this function, but since we don't 
  # TODO know where it is being used, it may cause things to break if changed
  my ($self, $t) = assertNumArgs(2, @_);
  $self->{timeout} = $t;
  $log->debug("changed timeout to $self->{timeout}");
}

1;
