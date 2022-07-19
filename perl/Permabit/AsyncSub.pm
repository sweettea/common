######################################################################
# Provides the ability to asynchronously start perl subroutines and
# later wait for the resulting return value, or error result.
#
# @synopsis
#
# Basic usage:
#
# use Permabit::AsyncSub;
# my $s = sub { #do stuff in background ... };
# my $task = Permabit::AsyncSub->new(code => $s, args => $args);
# $task->start();
# # do other stuff
# my $answer;
# eval {
#    $answer = $task->result();
# };
# if ($EVAL_ERROR) {
#     $log->error("backgound task threw $EVAL_ERROR");
#  }
#
#  Another usage pattern:
#
#  my $s = sub { # do other stuff in background };
#  my $task = Permabit::AsyncSub->new(code => $s)->start();
#  $task->wait();
#  $self->assert($task->status() eq 'error', "this stuff should fail");
#  my $error = $task->error();
#
# @description
#
# C<Permabit::AsyncSub>  allows you to run perl subroutines in the background
# and then get return values/objects back as well as exceptions. The module
# assumes that return value is a scalar and it can be any sort of compound
# object that Data::Dumper can serialize.
#
# $Id$
##
package Permabit::AsyncSub;

use strict;
use warnings FATAL => qw(all);

use Carp;
use Config;
use Data::Dumper;
use English qw(-no_match_vars);
use Log::Log4perl;
use POSIX qw(WIFSIGNALED WTERMSIG);
use Proc::Simple;
use Time::HiRes qw(usleep);
use Permabit::Assertions qw(
  assertDefined
  assertMinMaxArgs
  assertNumArgs
);
use Permabit::Tempfile;
use Permabit::Utils qw(
  getRandomSeed
);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

##
# @paramList{newProperties}
my %properties =
  (
   #########################
   # constructor arguments
   #########################

   # @ple the subroutine to execute in the asynchronous environment
   code => undef,

   # @ple the arguments to provide to the subroutine
   args => undef,

   # @ple signals to expect
   expectedSignals => [ ],

   # @ple whether we should kill the child proc on DESTROY()
   # (off by default).
   killOnDestroy => 0,

   # @ple the single to send the child proc if killOnDestroy is set
   # (SIGTERM by default).
   signalOnDestroy => 'SIGTERM',

   #########################
   # member variables
   #########################

   # the proc instance
   _proc => undef,

   # status of this subroutine invocation
   _status => undef,

   # temp file for results
   _tempfile => undef,
  );
##

######################################################################
# Instantiate a new AsyncSub
#
# @params{newProperties}
##
sub new {
  my $pkg = shift(@_);

  my $self = bless
    {
     %properties,
     @_,
    }, $pkg;


  assertDefined($self->{code}, "code not defined");

  foreach my $key (keys %{$self}) {
    if (!exists($properties{$key})) {
      confess("Invalid key passed to self: $key");
    }
  }

  $self->{_expectedSignalNums} = [ ];
  for my $sig (@{$self->{expectedSignals}}) {
    $sig =~ s/^SIG//;
    if (defined(signalNumber($sig))) {
      push @{$self->{_expectedSignalNums}}, signalNumber($sig);
    } else {
      confess("unknown signal $sig");
    }
  }

  $self->{_status} = "initialized";

  return $self;
}

my %sig_nums;
my @sig_names;

######################################################################
# convert signal name to signal number
##
sub signalNumber {
  my ($name) = assertNumArgs(1, @_);

  if (!%sig_nums) {
    unless($Config{sig_name} && $Config{sig_num}) {
      die("No sigs?");
    } else {
      my @names = split ' ', $Config{sig_name};
      @sig_nums{@names} = split ' ', $Config{sig_num};
      foreach (@names) {
        $sig_names[$sig_nums{$_}] ||= $_;
      }
    }
  }
  return $sig_nums{$name}
}

######################################################################
# Run this asynchronous subroutine.
#
# @return self
##
sub start {
  my ($self) = assertNumArgs(1, @_);

  if ($self->{_proc}) {
    croak("subroutine already started");
  }

  $self->{_tempfile} = new Permabit::Tempfile(SUFFIX => '.async', UNLINK => 1);

  my $code = $self->{code};
  my @args = defined($self->{args}) ? @{$self->{args}} : ( );
  my $file = $self->{_tempfile}->filename();

  my $wrapperSub = sub {
    srand(getRandomSeed());
    my $result;
    eval {
      $result = $code->(@args);
    };
    my $error;
    if ($EVAL_ERROR) {
      $error = $EVAL_ERROR;
      $log->debug("SimpleProc subprocess failed: $error, "
                  . "tmpfile: " . $file);
    }
    $self->{_tempfile}->unlink_on_destroy(0);
    my $data = Data::Dumper->Dump([ $result, $error, 1 ],
                                  [ qw( result error checkBit )]);
    open FH, ">$file" || POSIX::_exit(2);
    print FH $data, "\n";
    close FH || POSIX::_exit(2);
    POSIX::_exit(defined($error) ? 1 : 0);
  };

  $self->{_proc} = Proc::Simple->new();
  $self->{_proc}->kill_on_destroy($self->{killOnDestroy});
  $self->{_proc}->signal_on_destroy($self->{signalOnDestroy});
  if ($self->{_proc}->start($wrapperSub)) {
    $self->{_status} = "pending";
  } else {
    $log->debug("Proc::Simple::start failed: $OS_ERROR");
    $self->{_status} = "failure";
    $self->{_error}  = "FAILED to start asynchronous subroutine";
    $self->{_proc}   = undef;
  }

  return $self;
}

######################################################################
# Check what the status of the subprocess is
#
# @return one of 'initialized', 'pending', 'ok', 'error', or 'failure'
##
sub status {
  my ($self) = assertNumArgs(1, @_);

  if ($self->{_proc}) {
    if (!$self->{_proc}->poll()) {
      # read the result and clean up
      $self->wait();
    }
  }

  return $self->{_status};
}

######################################################################
# @return the pid of our proc
##
sub pid {
  my ($self) = assertNumArgs(1, @_);

  $self->{_proc} || croak("pid: no current process");
  return $self->{_proc}->pid();
}

######################################################################
# Check if the subprocess has completed
#
# @return A true value if the subprocess is done, otherwise a false value
##
sub isComplete {
  my ($self) = assertNumArgs(1, @_);

  $self->_poll();
  return (($self->{_status} ne "initialized")
          && ($self->{_status} ne "pending"));
}

######################################################################
# Wait for subroutine to finish if necessary, and then read the result
#
# @return self
##
sub wait {
  my ($self) = assertNumArgs(1, @_);

  while (!$self->isComplete()) {
    usleep(100 * 1000);
  }

  return $self->{_status};
}

sub _poll {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{_proc} && !$self->{_proc}->poll()) {
    my $exitStatus = $self->{_proc}->exit_status();
    my $procInfo = "proc exit status: " . $exitStatus . ", file: "
                   . $self->{_tempfile}->filename()
                   . ", pid: " . $self->{_proc}->pid();
    if (WIFSIGNALED($exitStatus)) {
      my $sig = WTERMSIG($exitStatus);
      if (scalar(grep { $sig == $_ } @{$self->{_expectedSignalNums}})) {
        $self->{_status} = "signal";
        $self->{_signal} = $sig;
        #$log->debug("caught expected signal $sig");
      } else {
        $self->{_status} = "failure";
        $self->{_error}  = "exit on signal " . $sig;
        $log->debug("caught unexpected signal $sig");
        ### TO DO: put stack trace in $self->{_traceback}
      }
    } else {
      our ($result, $error, $checkBit) = (undef, undef, undef);
      eval {
        do $self->{_tempfile}->filename();
      };
      if ($EVAL_ERROR) {
        $self->{_status} = "failure";
        $self->{_error} = $EVAL_ERROR;
        $log->debug("EVAL_ERROR: $self->{_error}; $procInfo");
      } elsif (!$checkBit) {
        $self->{_status} = "failure";
        $self->{_error} = "internal asyncsub error: bad data dump";
        $log->debug("$self->{_error}; $procInfo");
      } elsif (defined($error)) {
        $self->{_status} = "error";
        $self->{_error} = $error;
        $log->debug("ERROR: $self->{_error}; $procInfo");
      } else {
        $self->{_status} = "ok";
        $self->{_result} = $result;
      }
    }
    $self->{_tempfile} = undef;
    $self->{_proc}     = undef;
    return 0;
  }
  return 1;
}

######################################################################
# Kill this subroutine.
#
# @oparam sig   The signal used to kill the subroutine
#
# @return 1 if it succeeds in sending the signal, 0 otherwise.
##
sub kill {
  my ($self, $sig) = assertMinMaxArgs(1, 2, @_);
  if ($self->{_proc}) {
    return $self->{_proc}->kill($sig);
  }
}

######################################################################
# Wait for the subroutine to finish and return any error.
#
# @return    the error result if any or undef
##
sub error {
  my ($self) = assertNumArgs(1, @_);

  $self->wait();
  return $self->{_error};
}

######################################################################
# Wait for the subroutine to finish and return an expected signal.
#
# @return    the signal number
##
sub signal {
  my ($self) = assertNumArgs(1, @_);

  $self->wait();
  return $self->{_signal};
}

######################################################################
# Wait for the subroutine to finish and return the result, or croak
# if an error occurred
#
# @return    the return value of the subroutine
##
sub result {
  my ($self) = assertNumArgs(1, @_);

  $self->wait();

  if ($self->{_status} eq "ok" || $self->{_status} eq "signal") {
    return $self->{_result};
  }

  croak($self->{_error});
}

1;
