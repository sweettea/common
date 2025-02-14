##
# Base class to simplify use of Permabit::RSVP.
#
# @synopsis
#
# C<Permabit::RSVPer> is a base class that other classes can extend in
# order to have a simple interface to reserving and releasing servers.
# Instead of having to manage a L<Permabit::RSVP|Permabit::RSVP>
# object directly, subclasses can call L<"reserve"> and L<"release">
# to manage their reservations.
#
# $Id$
##
package Permabit::RSVPer;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Carp;
use List::Compare;
use Log::Log4perl;
use Socket;
use Storable qw(dclone);
use Sys::Hostname;

use Permabit::Assertions qw(
  assertMinArgs
  assertMinMaxArgs
  assertNumArgs
);
use Permabit::AsyncSub;
use Permabit::Constants;
use Permabit::RSVP;
use Permabit::Triage::Utils qw(
  getOwnerMoveToMaint
);
use Permabit::Utils qw(
  canonicalizeHostname
);

# Log4perl Logging object
my $log = Log::Log4perl->get_logger(__PACKAGE__);

##
# @paramList{new}
#
# Parameters defined here that are shared in common with C<Permabit::Testcase>
# will be "inherited" from that object.
my %PROPERTIES
  = (
     # @ple Whether to send a jabber message on RSVP release failures
     chatFailures      => undef,
     # @ple if a test can't clean up its machines, move them to maintenance
     moveToMaintenance => undef,
     # @ple The host running the rsvp daemon
     rsvpHost          => undef,
     # @ple The default key to use when reserving or releasing hosts
     rsvpKey           => undef,
     # @ple The default message to use when reserving or releasing hosts
     rsvpMsg           => undef,
     # @ple The default os class to use when reserving hosts
     rsvpOSClass       => undef,
     # @ple The port the rsvp daemon is listening on
     rsvpPort          => undef,
     # @ple Whether to send output on RSVP release failures to the real
     # stderr if stderr is being sent to a file
     stderrFailures    => undef,
    );
##

##########################################################################
# Construct a new RSVPer.  If either the rsvpHost or rsvpPort fields
# are set in the self hash, they will be used when constructing our
# L<Permabit::RSVP|Permabit::RSVP> object.  Otherwise the RSVP default
# will be used.  If the rsvpMsg field is set, it will be used as a
# default message when reserving or releasing hosts.
##
sub new {
  my $invocant = shift;
  my $class = ref($invocant) || $invocant;
  my $self = bless { %{ dclone(\%PROPERTIES) },
                     # Overrides previous values
                     @_,
                   }, $class;
  return $self;
}

##########################################################################
##
sub getParameters {
  assertNumArgs(0, @_);
  return [ keys(%PROPERTIES) ];
}

##########################################################################
# Release all reserved hosts and close the RSVP object.
#
# @oparam message       A message to provide when releasing hosts
##
sub closeRSVP {
  my ($self, $message) = assertMinMaxArgs(1, 2, @_);
  $self->releaseAll($message);
  if ($self->{_rsvp}) {
    $self->{_rsvp}->close();
    if ($self->{_callLog}) {
      $log->debug($self->{_callLog});
      $self->{_callLog} = '';
    }
  }
}

######################################################################
# Record a call in the call log
#
# @oparam args The name of the call and its arguments
##
sub _record {
  my ($self, @args) = @_;
  if (!$self->{_callLog}) {
    $self->{_callLog} = 'Call log';
  }
  @args = map { defined($_) ? $_ : '' } @args;
  $self->{_callLog} = join(';', $self->{_callLog}, join(',', @args));
}

##########################################################################
# See L<Permabit::RSVP/reserveHosts>
##
sub reserveHosts {
  my ($self, %params) = @_;
  $self->_record('reserveHosts', %params);
  my $rsvp = $self->_getRSVP();
  $params{key} ||= $self->{rsvpKey};
  $params{msg} ||= $self->{rsvpMsg};
  for (;;) {
    my $oldSlept = $self->getSecondsSlept();
    my @hosts = $rsvp->reserveHosts(%params);
    my $newSlept = $self->getSecondsSlept();

    if ($newSlept > $oldSlept) {
      eval {
        my $reserved = $self->{_reservedHosts};
        my $sleptRanges = $rsvp->{sleptRanges};
        my $newRange = pop (@$sleptRanges);
        push (@$newRange, scalar(keys %{$reserved}));
        push (@$sleptRanges, $newRange);
      };
      if ($EVAL_ERROR) {
        $log->error("Sleep range machine count failure: $EVAL_ERROR");
      }
    }

    my @tasks;
    foreach my $host (@hosts) {
      my $sub = sub {
        $self->checkMachine($host);
      };
      my $task = Permabit::AsyncSub->new(code => $sub);
      $task->start();
      push(@tasks, {host => $host, task => $task});
    }
    my $failures = 0;
    foreach my $t (@tasks) {
      my ($host, $task) = ($t->{host}, $t->{task});
      eval {
        $task->result();
      };
      if ($EVAL_ERROR) {
        ++$failures;
      }
    }
    if ($failures == 0) {
      my @ret;
      foreach my $t (@tasks) {
        my ($host, $task) = ($t->{host}, $t->{task});
        $self->{_reservedHosts}{$host} = 1;
        push(@ret, $host);
      }
      return @ret;
    }
    foreach my $t (@tasks) {
      my ($host, $task) = ($t->{host}, $t->{task});
      eval {
       $task->result();
       $rsvp->releaseHost(host => $host,
                          msg  => $params{msg},
                          key  => $params{key});
      };
      if ($EVAL_ERROR) {
        $log->debug("just-reserved host $host failed check"
                    . ", moving to maintenance: $EVAL_ERROR");
        $rsvp->moveToMaintenance(hosts    => [$host],
                                 message  => $params{msg} . ": " .$EVAL_ERROR,
                                 force    => 1);
      }
    }
  }
}

##########################################################################
# See L<Permabit::RSVP/reserveHostByName>
##
sub reserveHostByName {
  my ($self, %params) = @_;
  $self->_record('reserveHostsByName', %params);
  my $rsvp = $self->_getRSVP();
  $params{key} ||= $self->{rsvpKey};
  $params{msg} ||= $self->{rsvpMsg};
  $rsvp->reserveHostByName(%params);
  $self->{_reservedHosts}{$params{host}} = 1;
  if ((not defined($params{resource})) || (not $params{resource})) {
    $self->checkMachine($params{host});
  }
}

##########################################################################
# Determine if a host is associated with a specified class in RSVP.
#
# @param hostname       The hostname
# @param classname      The classname
#
# @return True if the host is associated with the class.
##
sub isClass {
  my ($self, $hostname, $classname) = assertNumArgs(3, @_);
  my @classes = $self->_getRSVP()->getClassInfo($hostname);
  return scalar(grep($classname eq $_, @classes));
}

##########################################################################
# Return any OS or architecture class listed in RSVP for a specific host.
#
# @param hostname  The hostname
#
# @return The associated OS and architecture classes, or an empty list
##
sub getHostOSArchClasses {
  my ($self, $hostname) = assertNumArgs(2, @_);
  my $rsvp = $self->_getRSVP();
  my @classes = ($rsvp->listOsClasses(), $rsvp->listArchitectureClasses());

  my @hostClasses = ();
  eval { @hostClasses = $rsvp->getClassInfo($hostname); };
  if ($EVAL_ERROR) {
    return undef;
  }

  my $lc = List::Compare->new(\@hostClasses, \@classes);
  my @intersection = $lc->get_intersection;

  return @intersection;
}

##########################################################################
# Return the names of the hosts reserved by this RSVP object.
#
# @return The list of hosts reserved.
##
sub getReservedHosts {
  my ($self) = assertNumArgs(1, @_);
  return (keys(%{$self->{_reservedHosts}}));
}

##########################################################################
# See L<Permabit::RSVP/release>
##
sub releaseHost {
  my ($self, %params) = @_;
  $self->_record('releaseHost', %params);
  $params{key} ||= $self->{rsvpKey};
  $params{msg} ||= $self->{rsvpMsg};
  $params{chatFailures} ||= $self->{chatFailures};
  $params{stderrFailures} ||= $self->{stderrFailures};

  # if the server is one that was reserved by this object, free it.
  if ($self->{_reservedHosts}{$params{host}}) {
    my $rsvp = $self->_getRSVP();
    $log->debug("releasing $params{host}\n");
    eval { $rsvp->releaseHost(%params) };
    if (my $releaseEval = $EVAL_ERROR) {
      $log->error("Unable to release $params{host}: $releaseEval");
      if ($self->{moveToMaintenance}) {
        $log->info("Attempting to move $params{host} into maintenance");
        eval {
          getOwnerMoveToMaint($params{host}, $releaseEval, $rsvp);
        };
        if (my $maintEval = $EVAL_ERROR) {
          $log->error("Unable to complete move to maintenance task(s):"
                    . " $maintEval");
        }
      }
    }
    delete($self->{_reservedHosts}{$params{host}});
  }
}

##########################################################################
# Call L<Permabit::RSVP/releaseHost> on all reserved hosts.
#
# @oparam message       A message to provide when releasing hosts
##
sub releaseAll {
  my ($self, $message) = assertMinMaxArgs(1, 2, @_);
  $self->_record('releaseAll');
  my @tasks;
  foreach my $host (keys(%{$self->{_reservedHosts}})) {
    my $sub = sub {
      $self->releaseHost(host => $host,
                         msg  => $message);
    };
    push(@tasks, Permabit::AsyncSub->new(code => $sub));
  }
  map { $_->start() } @tasks;
  map { $_->result() } @tasks;
  $self->{_reservedHosts} = {};
}

##########################################################################
# Renew all of our existing reservations.
#
# @param expire The new time at which the reservation should expire.
##
sub renewAll {
  my ($self, $expire) = assertNumArgs(2, @_);

  # renew all reservations
  my $rsvp = $self->_getRSVP();
  foreach my $host (keys %{$self->{_reservedHosts}}) {
    $rsvp->renewReservation(host => $host,
                            expire => $expire);
  }
}

######################################################################
# Renew a reservation on a host already reserved by this user.
#
# @param params{host}           The host whose reservation should be renewed
# @oparam params{expire}        The new expiration time
# @oparam params{msg}           The new reservation message
# @oparam params{user}          The user currently holding the reservation
#
# @croaks If the renew fails
##
sub renewReservation {
  my ($self, %params) = assertMinArgs(3, @_);
  $self->_getRSVP()->renewReservation(%params);
}

##########################################################################
# Forget about the reservation of a given server (ie, don't attempt to
# release it when the RSVPer is destroyed).  Warning, this is a good
# way to leak reservations, only do this if the reservation has some
# other mechanism for being released.
#
# @param host  The machine whose reservation should be forgotten.
##
sub forgetReservation {
  my ($self, $host) = assertNumArgs(2, @_);
  $self->_record('forgetReservation', $host);
  if ($self->{_reservedHosts}{$host}) {
    delete($self->{_reservedHosts}{$host});
    $log->warn("Forgetting reservation of $host");
  }
}

##########################################################################
# Remember about the reservation of a given server (ie, do attempt to
# release it when the RSVPer is destroyed).
#
# @param host  The machine whose reservation should be remembered.
##
sub rememberReservation {
  my ($self, $host) = assertNumArgs(2, @_);
  $self->_record('rememberReservation', $host);
  $self->{_reservedHosts}{$host} = 1;
  $log->info("Remembering reservation of $host");
}

######################################################################
# Check whether the given host is reserved by the current user and
# that it's ready to be used in tests.
#
# This will NOT add the host to the list of hosts reserved by this
# RSVPer.
#
# @param host   The host whose reservation to verify
#
# @croaks if the current user does not have the machine reserved or if
# the machine is not ready for use.
##
sub verifyReservation {
  my ($self, $host) = assertNumArgs(2, @_);
  my $rsvp = $self->_getRSVP();
  $rsvp->verify(host => $host);
  $self->checkMachine($host);
}

######################################################################
# Check whether the given host is suitable for running a test.
#
# @param host   The host to verify
#
# @croaks if the machine is not ready for use.
##
sub checkMachine {
  my ($self, $host) = assertNumArgs(2, @_);
  my $rsvp    = $self->_getRSVP();
  my $wait    = 15;
  my $retries = 4;
  for (my $i = 0;;) {
    my $msg = $rsvp->checkState("checking $host", $host);
    if (!$msg) {
      return;
    }
    if (++$i < $retries) {
      $log->debug("$host failed checkState: retry $i ($wait s)");
      sleep($wait);
    } else {
      croak("$host failed checkState: $msg");
    }
  }
}

##########################################################################
# Obtain a list of all machines in the reservation system and their
# status.  If verbose is not specified, each element of the list
# contains the hostname, reserving user, reservation expiration time,
# and reservation message.  Otherwise, each element contains the
# hostname, reserving user, and the list of classes to which the host
# belongs.
#
# @oparam params{user}           The user whose hosts should be listed
# @oparam params{class}          The class whose hosts should be listed
# @oparam params{verbose}        If class membership should be listed
# @oparam params{hostRegexp}     An optional regexp to filter list of hosts
#
# @return list of hosts.  each element: [hostname, user, rsvp until, message]
#         or [hostname, user, membership]
##
sub listHosts {
  my ($self, %params) = assertMinArgs(1, @_);
  return $self->_getRSVP()->listHosts(%params);
}

######################################################################
# Add an OS and hardware class to a host class list if needed.
#
# @param class   A list of classes, as a string or arrayref.

# @return        (String) list of classes, guaranteed to have an OS and
#                hardware class.
##
sub appendClasses {
  my ($self, $class) = assertNumArgs(2, @_);
  return $self->_getRSVP()->appendClasses($class);
}

##########################################################################
# Return a RSVP object initialized with parameters from $self
##
sub _getRSVP {
  my $self = shift;
  if (!$self->{_rsvp}) {
    my %args;
    if ($self->{rsvpHost}) {
      $args{dhost} = $self->{rsvpHost};
    }
    if ($self->{rsvpOSClass}) {
      $args{osClass} = $self->{rsvpOSClass};
    }
    if ($self->{rsvpPort}) {
      $args{dport} = $self->{rsvpPort};
    }
    $self->{_rsvp} = new Permabit::RSVP(%args);
  }
  return $self->{_rsvp};
}

#########################################################################
# Return a RSVP object's secondsSlept total.
#
# @return the total seconds slept since the last clear (or initialization)
##
sub getSecondsSlept {
  my ($self) = assertNumArgs(1, @_);
  return defined($self->{_rsvp}) ? $self->{_rsvp}{secondsSlept} : 0;
}

#########################################################################
# Clear a RSVP object's secondsSlept value(s)
#
# @return the total seconds slept since the last clear (or initialization)
##
sub clearSecondsSlept {
  my ($self) = assertNumArgs(1, @_);
  my $seconds = $self->getSecondsSlept();
  if (defined($self->{_rsvp})) {
    $self->{_rsvp}->{secondsSlept} = 0;
  }
  return $seconds;
}

#########################################################################
# Return a RSVP object's sleptRanges value
##
sub getSleptRanges {
  my ($self) = assertNumArgs( 1, @_ );
  my @array = ();
  if (defined($self->{_rsvp})) {
    my $rsvp = $self->{_rsvp};
    if (defined($rsvp->{sleptRanges})) {
      my $arrRef = $rsvp->{sleptRanges};
      push(@array, @$arrRef);
    }
  }
  return @array;
}

#########################################################################
# Set a RSVP object's sleptRanges value
##
sub clearSleptRanges {
  my ($self) = assertNumArgs(1, @_);
  if (defined($self->{_rsvp})) {
    $self->{_rsvp}->{sleptRanges} = undef;
  }
}

1;
