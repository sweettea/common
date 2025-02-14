##
# Perl interface to Permabit machine reservation system
#
# @synopsis
#
#     use Permabit::RSVP;
#     $rsvp = Permabit::RSVP->new();
#     $rsvp->reserveHostByName(host => "host-1",
#                              expire => time() + 10*60,
#                              msg => "performance testing");
#     $rsvp->releaseHost(host => "host-1",
#                        msg => "performance testing");
#     my @at@hosts = $rsvp->reserveHosts(numhosts => 5,
#                                     expire => time() + 10*60,
#                                     msg => "performance testing",
#                                     wait => 1);
#
# @description
#
# C<Permabit::RSVP> provides an object oriented interface to the
# Permabit machine reservation system.  It can be used to reserve
# hosts, release reservations, list reservations, etc.
#
# $Id$
##
package Permabit::RSVP;

use strict;
use warnings FATAL => qw(all);
use Carp;
use Data::Dumper;
use English qw(-no_match_vars);
use IO::Socket;
use List::MoreUtils qw(uniq);
use Log::Log4perl;
use Storable qw(dclone);
use Sys::Hostname;

use Permabit::Assertions qw(
  assertDefined
  assertMinArgs
  assertMinMaxArgs
  assertNumArgs
);
use Permabit::Configured;
use Permabit::Constants;
use Permabit::INETSocket;
use Permabit::Utils qw(
  attention
  getUserName
  reallySleep
  sendChat
  sendMail
  shortenHostName
);
use Permabit::PlatformUtils qw(
  getDistroInfo
  getReleaseInfo
);
use Permabit::SystemUtils qw(
  runSystemCommand
);
use Permabit::Triage::Utils qw(
  getTriagePerson
);

use base qw(Exporter Permabit::Configured);

our @EXPORT_OK = qw(listArchitectureClasses listHardwareClasses listOsClasses);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
# Determine the default RSVP server.
#
# @return The default rsvp server
##
sub _getDefaultRSVPServer {
  my ($self) = assertNumArgs(1, @_);
  return $self->{defaultRSVPServer};
}

######################################################################
# @inherit
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);
  # Make sure we've got all the values we may need much later for
  # error reporting if things go south.
  assertDefined($self->{defaultRSVPServer});
  # Implement defaults
  $self->{dport} //= 1752;
  $self->{releaseRetryCount} //= 4;
  $self->{releaseRetryTimeout} //= 2;
  $self->{reserveRetryTimeout} //= 15;
  $self->{retryMultiplier} //= 2;
  $self->{secondsSlept} //= 0;
  $self->{user} //= getUserName();
  $self->{verbose} //= 0;
  # The config file must set defaultRSVPServer.
  # The environment variable PRSVP_HOST can override that.
  # The caller may pass in "dhost" (e.g., with a value from the command
  # line) to override both, whereas passing in defaultRSVPServer would not
  # override $PRSVP_HOST.
  $self->{dhost} //= ($ENV{PRSVP_HOST} // $self->{defaultRSVPServer});
}

######################################################################
# Reconstitute a data structure from the wire
#
# @param line   the line received off the wire
#
# @return (command, parameters)
##
sub _decode {
  my $line = shift;
  my $VAR1;                     # created by the pack() statement

  $line =~ /^(\S+)\s*(\S*)/;
  my ($cmd, $serialized) = ($1, $2);

  my $ref;
  if ($serialized) {
    $ref = eval(pack ("h*", $serialized));
  }
  $log->debug("RECEIVED $cmd: " . _toString($ref));

  return ($cmd, $ref);
}

######################################################################
# Open a connection to the rsvp server
#
# @return the connection
##
sub _open {
  my ($self) = assertNumArgs(1, @_);

  my $host = $self->{dhost};
  $log->debug("Connecting to $host");
  while (1) {
    my $ret = Permabit::INETSocket->new(Proto     => 'tcp',
                                        PeerAddr  => $host,
                                        PeerPort  => $self->{dport});
    if ($ret) {
      return $ret;
    }
    if (!$ERRNO{EINTR}) {
      croak("Can't locate server on $host:$self->{dport}: $!\n"
            . "\tYou probably need to run a server");
    }
  }
}

######################################################################
# Do nothing for the benefit of other code calling this.
##
sub close {
  my ($self) = assertNumArgs(1, @_);
}

######################################################################
# Issue a request to the rsvp server and get a response.
#
# @param cmd            The name of the command being sent
# @param params         The parameters of that command
# @param checkResult    Whether or not to check the result of the command
#
# @return result of the command
##
sub _request {
  my ($self, $cmd, $params, $checkResult) = assertNumArgs(4, @_);
  my $serialized = $cmd . " " . unpack ("h*", _toString($params)) . "\n";
  if ($log->is_debug()) {
    $log->debug("SENT $cmd: " . _toString($params));
  }

  my $fh = $self->_open();
  print $fh $serialized;

  my $ret = 0;
  local $/ = "\n";
  while (defined(my $line = <$fh>)) {
    chomp $line;
    my ($rspCmd, $rspParams) = _decode($line);
    if ($rspCmd eq "DONE") {
      # We're done
      $fh->close();
      if ($checkResult) {
        $self->_checkResult($ret);
      }
      return $ret;
    }
    if ($rspCmd ne $cmd) {
      # mismatched response
      $fh->close();
      croak("Bad response to $cmd: $rspCmd");
    }
    $ret = $rspParams;
  }
  $fh->close();
  # We didn't get a DONE
  croak("Poorly terminated response to $cmd, got "
        . ($ret ? $ret->{message} : "0"));
}

######################################################################
# Add a class to the reservation system.
#
# @param params{class}          The name of the class to add
# @oparam params{members}       A listref of the class names which
#                                make up this class
# @oparam params{description}   Descriptive message for class
##
sub addClass {
  my ($self, %params) = assertMinArgs(3, @_);
  $params{members} ||= [];
  $params{description} ||= '';
  $self->_request('add_class', \%params, 1);
}

######################################################################
# Add a resource class to the reservation system.
#
# @param params{class}          The name of the class to add
# @oparam params{description}  Descriptive message for resource class
##
sub addResourceClass {
  my ($self, %params) = assertMinArgs(3, @_);
  $params{description} ||= '';
  $self->_request('add_resource_class', \%params, 1);
}

######################################################################
# Add one host to the reservation system.
#
# @param params{host}           The hostname of the host to add
# @oparam params{classes}       A listref of class names to which the
#                               host belongs.
##
sub addHost {
  my ($self, %params) = assertMinArgs(3, @_);
  $params{classes} ||= [];
  my $msg = $self->_checkReleaseState($params{host});
  if ($msg) {
    croak("Host $params{host} is not in state suitable to "
          . "add to rsvp: $msg");
  }
  $self->_request('add_host', \%params, 1);
}

######################################################################
# Add a resource to the reservation system.
#
# @param params{resource}     The hostname of the host to add
# @oparam params{class}       The class name to which the resource belongs
##
sub addResource {
  my ($self, %params) = assertMinArgs(3, @_);
  $params{class} ||= "";
  $self->_request('add_resource', \%params, 1);
}

######################################################################
# Take an arrayref or string of class list, and return a list.
#
# @param class  A list of classes, as a string or arrayref.
#
# @return The list, as a list.
##
sub _classesAsList {
  my ($self, $class) = assertNumArgs(2, @_);
  if (ref($class) eq "ARRAY") {
    return $class;
  }

  return [split(",", $class)];
}

#######################################################################
# Take an arrayref or string of class list, and return a list.
#
# @param class  A list of classes, as a string or arrayref.
#
# @return The list, as a string.
##
sub _classesAsString {
  my ($self, $class) = assertNumArgs(2, @_);
  if (ref($class) eq "ARRAY") {
    return join(",", @$class);
  }

  return $class;
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
  $class ||= '';
  $class = $self->_classesAsList($class);

  $self->appendOSClass($class);
  $self->appendFarm($class);

  # Return the (possibly-modified) class list
  return $self->_classesAsString($class);
}

######################################################################
# Appends FARM to the classList if no hardware class is in the list.
#
# @param  $classList  arrayref of class list
#
##
sub appendFarm {
  my ($self, $classList) = assertNumArgs(2, @_);

  foreach my $class (@$classList) {
    if (grep { $class eq uc($_) } @{$self->{classes}->{hardware}}) {
      return;
    }
  }
  push(@$classList, "FARM");
}

######################################################################
# Appends an OS Class to the classList if we think we need one.
#
# @param  $classList  arrayref of class list
#
# @return             Boolean indicating yes or no.
##
sub appendOSClass {
  my ($self, $classList) = assertNumArgs(2, @_);

  my @osLikeClasses = (
                       @{$self->{classes}->{os}},
                       'ALL',
                      );
  foreach my $class (@$classList) {
    if (grep { $class eq uc($_) } @osLikeClasses) {
      # It already has an OS! Hurray!
      return;
    }
  }

  # It does not have an OS class, use the first one of: (1) the osClass
  # property, (2) the current machine's OS, (3) the last ditch default.
  my $osClass = $self->{osClass};
  if (!defined($osClass)) {
    eval {
      $osClass = uc(getDistroInfo());
    };
    if ($EVAL_ERROR) {
      $log->error("getDistroInfo() exception: $EVAL_ERROR");
    }
  }
  $osClass //= uc(getReleaseInfo('albireo')->{defaultRelease});

  push(@$classList, $osClass);
}

######################################################################
# Deleted a class from the reservation system.
#
# @param params{class}          The name of the class to delete
##
sub delClass {
  my ($self, %params) = assertNumArgs(3, @_);
  $self->_request('del_class', \%params, 1);
}

######################################################################
# Delete one host from the reservation system.
#
# @param params{host}           The hostname of the host to delete
##
sub delHost {
  my ($self, %params) = assertNumArgs(3, @_);
  $self->_request('del_host', \%params, 1);
}

######################################################################
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

  $params{user}       ||= "";
  $params{class}      ||= "";
  $params{class}        = $self->_classesAsString($params{class});
  $params{hostRegexp} ||= "";
  $params{verbose}    ||= 0;
  my $result = $self->_request('list_hosts', \%params, 0);
  if ($result->{type} eq "ERROR") {
    croak($result->{message});
  }
  return $result->{data};
}

######################################################################
# Obtain information about classes in the reservation system. If
# params{class} is not set, a list of all classes in the reservation
# system, their description and direct member classes are returned.
# Otherwise, a list of the direct and derived member hosts for the
# specified class is returned.
#
# @oparam params{class}          The class whose hosts should be listed
#
# @return list of classes.  each element: ...
##
sub listClasses {
  my ($self, %params) = assertMinArgs(1, @_);

  $params{class} ||= "";
  $params{class}   = $self->_classesAsString($params{class});
  my $result = $self->_request('list_classes', \%params, 0);
  if ($result->{type} eq "ERROR") {
    croak($result->{message});
  }
  return $result->{data};
}

######################################################################
# List the Architecture classes
##
sub listArchitectureClasses {
  my @classes = sort(@{Permabit::RSVP->new()->{classes}->{architecture}});
  return @classes;
}

######################################################################
# List the Hardware classes
##
sub listHardwareClasses {
  my @classes = sort(@{Permabit::RSVP->new()->{classes}->{hardware}});
  return @classes;
}

######################################################################
# List the O/S classes
##
sub listOsClasses {
  my @classes = sort(@{Permabit::RSVP->new()->{classes}->{os}});
  return @classes;
}

######################################################################
# Modify the list of classes that this host belongs to.
#
# @param params{host}           The host to modify
# @oparam params{addClasses}    The list of classes to add to this host
# @oparam params{delClasses}    The list of classes to delete from this host
##
sub modifyHost {
  my ($self, %params) = assertMinArgs(3, @_);

  $params{user} ||= $self->{user};
  $params{addClasses} ||= [];
  $params{delClasses} ||= [];
  if (grep($_ eq 'MAINTENANCE', @{$params{delClasses}})
        && (my $msg = $self->_checkReleaseState($params{host}))) {
    # It's a hack to hardcode MAINTENANCE here, but we don't have a
    # way to query the rsvp server for the list of resource classes
    croak("Host $params{host} is not in state suitable to "
          . "remove from MAINTENANCE class: $msg");
  }

  $self->_request('modify_host', \%params, 1);
}

######################################################################
# Add a next user to a host that is already reserved by some other user
#
# @param params{host}          The host to add next user to
# @oparam params{user}         The next user
# @oparam params{expire}       How long to reserve this server for
# @oparam params{msg}          Descriptive message for reservation
#
# @croaks If the add fails
##
sub addNextUser {
  my ($self, %params) = assertMinArgs(3, @_);
  $self->_initReserveParams(\%params);
  $self->_request('add_next_user', \%params, 1);
}

######################################################################
# Delete the next user of a host
#
# @param params{host}          The host to delete the next user from
# @oparam params{user}         The next user
#
# @croaks If the delete fails
##
sub delNextUser {
  my ($self, %params) = assertMinArgs(3, @_);
  $params{user} ||= $self->{user};
  $self->_request('del_next_user', \%params, 1);
}

######################################################################
# Release a reservation on a host, or all hosts reserved by this user.
#
# @oparam params{host}           The host to release
# @oparam params{all}            All hosts reserved by this user
#                                should be released
# @oparam params{user}           The user releasing the host(s)
# @oparam params{msg}            A message to log when releasing
# @oparam params{key}            The key provided when reserving the host
# @oparam params{force}          Ignore the locking key (use with caution)
# @oparam params{chatFailures}   Send a chat message to params{user} before
#                                croaking
# @oparam params{stderrFailures} Write release failures to stderr before
#                                croaking
#
# @croaks If the release fails
##
sub releaseHost {
  my ($self, %params) = assertMinArgs(3, @_);

  my $chatFailures = $params{chatFailures};
  my $stderrFailures = $params{stderrFailures};
  delete $params{chatFailures};
  delete $params{stderrFailures};

  $params{msg}  ||= "";
  $params{user} ||= $self->{user};
  my @hosts = $self->_getHostsToRelease(\%params);

  my $error;
  my $timeout = $self->{releaseRetryTimeout};
  for (my $i = 0; $i < $self->{releaseRetryCount}; $i++) {
    foreach my $host (@hosts) {
      $params{host} = $host;

      # Verify host ownership before doing any additional checks.
      $log->debug("Verifying ownership: $host");
      $self->_request('verify_rsvp', {host => $params{host},
                                      user => $params{user}}, 1);

      $error = $self->_checkReleaseState($host, $params{user});
      if ($error) {
        next;
      }

      $log->debug("Attempting to release: $host");
      $self->_request('release_rsvp', \%params, 1);
      # Host is released, remove from list
      @hosts = grep {$_ ne $host} @hosts;
    }

    if (!@hosts) {
      last;
    }
    reallySleep($timeout);
    $timeout *= $self->{retryMultiplier};
  }

  if (@hosts) {
    my $msg = "Unable to release " . join(',', @hosts)
      . " in $self->{releaseRetryCount} attempts: $error";
    my $fullMessage = "$msg\n$params{msg}\n";
    if ($chatFailures) {
      eval {
        if ($params{user} eq 'nightly') {
          # Don't bother; we have automated tools that cleanup nightly.
        } elsif ($params{user} eq 'continuous') {
          sendChat("testing", undef, "Release Host Error", $fullMessage);
        } else {
          sendChat(undef, $params{user}, "Release Host Error", $fullMessage);
        }
      };
      if ($EVAL_ERROR) {
        $log->error("couldn't notify anyone of leaked host(s): $fullMessage"
                    . "\nexception: $EVAL_ERROR");
      }
    }
    if ($stderrFailures) {
      attention($fullMessage);
    }
    croak($msg);
  }
}

######################################################################
# Release a reservation on a resource
#
# @param params{resource}       The resource to release
# @oparam params{user}          The user releasing the resource
# @oparam params{msg}           A message to log when releasing
# @oparam params{key}           The key provided when reserving the resource
# @oparam params{force}         Ignore the locking key (use with caution)
#
# @croaks If the release fails
##
sub releaseResource {
  my ($self, %params) = assertMinArgs(3, @_);

  $params{msg} ||= "";
  $params{user} ||= $self->{user};
  $self->_request('release_resource', \%params, 1);
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
  $params{user} ||= $self->{user};
  $params{msg} ||= "";
  $params{expire} ||= time() + $DAY;

  $self->_request('renew_rsvp', \%params, 1);
}

######################################################################
# Reserve one or more machines in a given reservation class.  A list
# of hostnames is returned.  The expiration time is given as seconds
# since the epoch; relative times may be computed with "time() +
# seconds from now."  The optional message argument can be used to
# indicate an intended use or other such notes.
#
# @param  params{numhosts}  The number of hosts or resources to reserve
# @param  params{class}     The class to which they must belong
# @oparam params{expire}    How long to reserve them for
# @oparam params{msg}       Descriptive message for reservation
# @oparam params{user}      The user reserving these hosts or resources
# @oparam params{wait}      Whether or not to retry the reservation
#                           attempt if it fails
# @oparam params{key}       A key that must be provided at release time,
#                           to prevent accidental release
#
# @return The list of hosts or resources that were reserved
#
# @croaks If the reserve fails
##
sub _reserveByClass {
  my ($self, %params) = assertMinArgs(3, @_);
  $self->_initReserveParams(\%params);
  my $msg = "reserve $params{numhosts} hosts in $params{class}";
  my $ret = $self->_reserveWithRetries("rsvp_class", \%params, $msg);
  return @{$ret->{data}};
}

######################################################################
# Reserve one machine.  The expiration time is given as seconds
# since the epoch; relative times may be computed with "time() +
# seconds from now."  The optional message argument can be used to
# indicate an intended use or other such notes.
#
# @param  params{host}      The host to be reserved.
# @oparam params{expire}    How long to reserve this server for
# @oparam params{msg}       Descriptive message for reservation
# @oparam params{user}      The user who is reserving this host
# @oparam params{wait}      Whether or not to retry the reservation
#                           attempt if it fails
# @oparam params{key}       A key that must be provided at release time,
#                           to prevent accidental release
# @oparam params{resource}  Specify that the host to be reserved is actually
#                           a resource.
#
# @croaks If the reserve fails
##
sub reserveHostByName {
  my ($self, %params) = assertMinArgs(2, @_);
  $self->_initReserveParams(\%params);
  $self->_reserveWithRetries("rsvp_host", \%params, "reserve $params{host}");
}

######################################################################
# Reserve one or more machines from the default class.  A list of
# hostnames is returned.  The expiration time is given as seconds
# since the epoch; relative times may be computed with "time() +
# seconds from now."  The optional message argument can be used to
# indicate an intended use or other such notes.
#
# @param  params{numhosts}  The number of hosts to reserve
# @oparam params{expire}    How long to reserve these servers for
# @oparam params{msg}       Descriptive message for reservation
# @oparam params{randomize} Whether the server should randomize the available
#                           host list before selecting.
# @oparam params{user}      The user who is reserving these hosts
# @oparam params{wait}      Whether or not to retry the reservation
#                           attempt if it fails
#
# @return The list of hosts that were reserved
#
# @croaks If the reservation fails
##
sub reserveHosts {
  my ($self, %params) = assertMinArgs(3, @_);
  $params{class} ||= "";
  $params{class} = $self->appendClasses($params{class});
  return $self->_reserveByClass(%params);
}

######################################################################
# Reserve one or more resources in a given resource class.  A list
# of resource names is returned.  The expiration time is given as seconds
# since the epoch; relative times may be computed with "time() +
# seconds from now."  The optional message argument can be used to
# indicate an intended use or other such notes.
#
# @param  params{numresources}  The number of resources to reserve
# @param  params{class}          The class to which the resources must belong
# @oparam params{expire}         How long to reserve these servers for
# @oparam params{msg}            Descriptive message for reservation
# @oparam params{user}           The user who is reserving these resources
# @oparam params{wait}           Whether or not to retry the reservation
#                                attempt if it fails
#
# @return The list of resources that were reserved
#
# @croaks If the reserve fails
##
sub reserveResources {
  my ($self, %params) = assertMinArgs(3, @_);
  $params{numhosts} = $params{numresources};
  delete $params{numresources};
  return $self->_reserveByClass(%params);
}

######################################################################
# Verify a reservation on a host.  Will croak if the host is not owned
# by the given user.
#
# @param params{host}   The host whose reservation is in question
# @oparam params{user}  The user expected to have the host reserved
##
sub verify {
  my ($self, %params) = assertMinArgs(3, @_);
  $params{user} ||= $self->{user};
  $self->_request('verify_rsvp', \%params, 1);
}

######################################################################
# Initialize parameters for reserveHost[s].
##
sub _initReserveParams {
  my ($self, $params) = assertNumArgs(2, @_);

  $params->{expire} ||= time() + $DAY;
  $params->{user}   ||= $self->{user};

  my $machine = shortenHostName(hostname());
  if ($params->{msg}) {
    $params->{msg} = "$machine($PID): $params->{msg}";
  } else {
    $params->{msg} = "reserved from: $machine($PID)";
  }
}

######################################################################
# A utility method that processes the "wait" parameter on a reserve
# hosts request, optionally retrying it until it either succeeds or
# fails with a permanent error.
#
# @param function   The name of the method to call
# @param params     Hashref of params to the method
# @param action     The name of the action to perform, for debugging messages
#
# @return the result of the method
##
sub _reserveWithRetries {
  my ($self, $function, $params, $action) = assertNumArgs(4, @_);
  my $result;

  # Extract the wait parameter, which will be processed here.
  my $wait = $params->{wait};
  delete($params->{wait});

  if ($wait) {
    # The wait parameter is set, so retry the request until it succeeds.
    $wait = $self->{reserveRetryTimeout};
    my $maxWait = 3 * $MINUTE;
    my $start = time();
    for (;;) {
      $result = $self->_request($function, $params, 0);
      if (($result->{type} eq "ERROR") && $result->{temporary}) {
        $log->warn("Tried to $action and failed ($result->{message}), "
                   . "sleeping $wait before retrying");
        $self->{secondsSlept} += $wait;
        $self->addNewSleepRange($start, $wait);
        reallySleep($wait);
        $wait *= $self->{retryMultiplier};
        if ($wait > $maxWait) {
          $wait = $maxWait;
        }
      } else {
        last;
      }
    }
  } else {
    # When the wait parameter is not set, just do the request once.
    $result =  $self->_request($function, $params, 0);
  }
  # It makes the code simpler if we call checkResult in only one
  # place.  Here it is:
  $self->_checkResult($result);
  return $result;
}

######################################################################
# A utility method that will add a new rsvp sleep range to the list
##
sub addNewSleepRange {
  my ($self, $start, $wait) = assertNumArgs(3, @_);

  eval {
    my $r = [$start, $wait];
    if (!defined($self->{sleptRanges})) {
      $self->{sleptRanges} = [ $r ];
    } else {
      my $ranges = $self->{sleptRanges};
      if ($start == $ranges->[$#$ranges]->[0]) {
        $ranges->[$#$ranges] = $r;
      } else {
        push(@$ranges, $r);
      }
    }
  };
  if ($EVAL_ERROR) {
    $log->error("Sleep range creation failure: $EVAL_ERROR");
  }
}

######################################################################
# Utility method that returns the list of hosts specified by this
# release request.
##
sub _getHostsToRelease {
  my ($self, $params) = assertNumArgs(2, @_);

  if ($params->{host}) {
    return ($params->{host});
  }

  delete $params->{all};
  my $hostDescriptors = $self->listHosts(user => $params->{user});
  return map {$_->[0]} @{$hostDescriptors};
}

######################################################################
# Check if a given host is ready to be put into the general
# reservation pool.
#
# @param host   The host in question
# @oparam user  The user attempting to release the host.  Defaults to
#               checking for any processes by non root users
#
# @return undef if the host is ready to be released, an error string otherwise
##
sub _checkReleaseState {
  my ($self, $host, $user) = assertMinMaxArgs(2, 3, @_);
  return $self->checkState("Checking if ready to release $host", $host, $user);
}

######################################################################
# Check if a given host is ready to be put into the general
# reservation pool.
#
# @param msg    The debug message to print out
# @param host   The host in question
# @oparam user  The user attempting to release the host.  Defaults to
#               checking for any processes by non root users
#
# @return undef if the host is ready to be released, an error string otherwise
##
sub checkState {
  my ($self, $msg, $host, $user) = assertMinMaxArgs(3, 4, @_);

  $log->debug($msg);
  my @message = $self->runAthinfo($host, "checkServer");
  if (join(' ', @message) !~ /^\s*success\s*$/) {
    my $msg = join("\n\t", @message);
    $log->error("checkServer failed on $host:\t$msg");
    return $msg;
  }

  my @ps = $self->runAthinfo($host, "ps");
  if ($ps[0] eq "FAILURE") {
    my $msg = "Couldn't run ps on $host: $ps[1]";
    $log->error($msg);
    return $msg;
  }
  # ps SOMETIMES truncates username to 7 characters, so only match on
  # that :-(
  my $userPattern;
  if ($user) {
    if (length($user) > 7) {
      $userPattern = substr($user, 0, 7) . "\\w";
    } else {
      $userPattern = "${user}";
    }
  }

  # Create the non "root" line-checking regex from RSVP's configuration.
  my $lineRegex = join("|", @{$self->{processes}->{ok}->{root}});
  $lineRegex = qr/($lineRegex)\s/x;

  # Remove the header line
  shift(@ps);
  foreach my $line (@ps) {
    # note that on Windows, username is right-aligned
    if ($userPattern
        && $line =~ /^\s*${userPattern}\s/
        && !grep {$line =~ /\W$_(\s|$)/} @{$self->{processes}->{ok}->{user}}) {
      my $msg = "FOUND PROCESS on $host: $line";
      $log->error($msg);
      return $msg;
    }
    foreach my $p (@{$self->{processes}->{taboo}}) {
      if (grep {$line
          =~ /\W\Q$_\E\s/} @{$self->{processes}->{ok}->{nonUser}}) {
        next;
      } elsif ($line =~ /\W\Q$p\E\s/) {
        my $msg = "FOUND PROCESS on $host: $line";
        $log->error($msg);
        return $msg;
      }
    }
    # warn if there are non "root" processes found, but still
    # release as long as they're not on the forbidden list
    if ($line !~ /$lineRegex/) {
      $log->warn("FOUND PROCESS on $host: $line");
    }
  }
  return undef;
}

######################################################################
# Write the message about a machine going into maintenance.
#
# @param params             the hash used by moveToMaintenance
# @param host               the host
# @param oldClasses         a listref of the old classes
# @param owner              the owner of the reservation (or undef)
# @param reservationMessage the reservation message
#
# @return a message as a string
##
sub _getMaintenanceMessage {
  my ($self, $params, $host, $oldClasses, $owner, $reservationMessage)
    = assertNumArgs(6, @_);

  my $message = <<EOM;
$host was moved to maintenance by $self->{user}.
{noformat:title=Message}
$params->{message}
{noformat}
EOM
  if ($owner) {
    $message .= "\nReservation was held by: $owner";
  }
  if ($reservationMessage) {
    $message .= "\nReservation message: $reservationMessage";
    $reservationMessage =~ s:/: :g;
    $message .= "\nSearchable reservation message: $reservationMessage"
  }

  if (@{$oldClasses}) {
    my $cleanFarm = "cleanFarm.sh";
    if (defined($self->{toolDir})) {
      $cleanFarm = "$self->{toolDir}/$cleanFarm";
    }
    $message .=
      "\n\nRun one of the following commands to put $host back in RSVP\n"
        . "\t$cleanFarm -m $host\n"
        . "OR\n"
        . "\trsvpclient modify $host --del MAINTENANCE --add "
        . join(',', @{$oldClasses}) . "\n";
  }
  return $message;
}

######################################################################
# Send information about a machine being moved to maintenance.
#
# @param params        the hash used by moveToMaintenance
# @param host          the hostname being moved
# @param oldClasses    a listref to the old classes
##
sub _notifyMaintenance {
  my ($self, $params, $host, $oldClasses) = assertNumArgs(4, @_);

  my ($owner, undef, $reservationMessage)
    = $self->getOwnerInfo($host, 'MAINTENANCE');
  $reservationMessage ||= "";
  my ($firstLine) = split(/\n/, $params->{message});
  my $hostDistro = getDistroInfo($host);
  my $rsvpMsg = "(DISTRO:$hostDistro) " . $reservationMessage . ", " . $firstLine;
  if ($params->{assignee}) {
    eval {
      $self->addNextUser(host => $host,
                         user => $params->{assignee},
                         msg  => $rsvpMsg);
    };
    if ($EVAL_ERROR) {
      if ($EVAL_ERROR =~ m/user (.*) at/g) {
        $self->delNextUser(host => $host,
                           user => $1);
        $self->addNextUser(host => $host,
                           user => $params->{assignee},
                           msg  => $rsvpMsg);
      } else {
        die($EVAL_ERROR);
      }
    }
  }
  if ($params->{assignee} || $params->{force}) {
    eval {
      $self->releaseResource(resource => $host,
                             user     => $owner,
                             msg      => $rsvpMsg,
                             force    => 1);
    };
    if ($EVAL_ERROR) {
      $log->error("Error during releaseResource: $EVAL_ERROR");
    }
  }

  my $subject = "$host in maintenance: $params->{message}";
  my $message = $self->_getMaintenanceMessage($params, $host, $oldClasses,
                                              $owner, $reservationMessage);
  if ($owner && $owner ne 'DEATH' && !$params->{force}) {
    if (defined($self->{emailDomain})) {
      my $destination = ["${owner}\@$self->{emailDomain}"];
      sendMail("$self->{user}\@$self->{emailDomain}", $destination, $subject,
               undef, $message);
    }
    eval {
      sendChat(undef, $owner, "Maintenance Notification", $message);
    };
  }
}

######################################################################
# Move a machine into the RSVP MAINTENANCE class.
#
# @param  params{hosts}         The hosts to move
# @oparam params{message}       Reason for moving machines
# @oparam params{force}         Force a message if needed, do not send mail
# @oparam params{assignee}      Owner of issue
#
# @croaks If the move fails
##
sub moveToMaintenance {
  my ($self, %params) = assertMinArgs(3, @_);

  if (!$params{message}) {
    if ($params{force}) {
      $params{message} = "forced release of " . join(" ", @{$params{hosts}});
    } else {
      croak("A message must be supplied for move_to_maintenance");
    }
  }

  $params{assignee} ||= getTriagePerson($params{project});

  foreach my $host (@{$params{hosts}}) {
    if ($self->isInMaintenance($host)) {
      next;
    }
    my @oldClasses = $self->getClassInfo($host);
    $self->modifyHost(
                      host            => $host,
                      addClasses      => ['MAINTENANCE'],
                      delClasses      => \@oldClasses,
                     );
    $self->_notifyMaintenance(\%params, $host, \@oldClasses);
  }
}

######################################################################
# Check if this host exists in RSVP.
#
# @param rsvp           The rsvp object to use
# @param hostname       The name of the host to check
#
# @return A true value if the host exists in RSVP.
##
sub isInRsvp {
  my ($self, $hostname) = assertNumArgs(2, @_);
  my $machs = $self->listHosts;
  foreach my $m (@{$machs}) {
    if ($m->[0] eq $hostname) {
      return 1;
    }
  }
}

######################################################################
# Check if this host is already in the RSVP MAINTENANCE class.
#
# @param rsvp           The rsvp object to use
# @param hostname       The name of the host to check
#
# @return A true value if the host is in the MAINTENANCE class.
##
sub isInMaintenance {
  my ($self, $hostname) = assertNumArgs(2, @_);
  return $self->isInClass($hostname, 'MAINTENANCE');
}

######################################################################
# Check if this host is in a specific RSVP class.
#
# @param rsvp           The rsvp object to use
# @param hostname       The name of the host to check
# @param class          The name of a class to check for membership in
#
# @return A true value if the host is in the MAINTENANCE class.
##
sub isInClass {
  my ($self, $hostname, $class) = assertNumArgs(3, @_);
  my $list = $self->listHosts(verbose    => 1,
                              class      => $class,
                              hostRegexp => $hostname,
                             );
  foreach my $info (@{$list}) {
    if ($info->[0] eq $hostname) {
      return 1;
    }
  }
  return 0;
}

######################################################################
# Get the owner of the machine from RSVP.
#
# @param  hostname       The name of the host to check
# @oparam class          The classes to look for hosts in.
#
# @return A list of the owner, the reservation timelimit and the reservation
# message if the machine in RSVP, or undef if unowned or not in RSVP.
##
sub getOwnerInfo {
  my ($self, $hostname, $class) = assertMinArgs(2, @_);
  my $list = $self->listHosts(hostRegexp => $hostname, class => $class);
  foreach my $info (@{$list}) {
    if ($info->[0] eq $hostname) {
      return ($info->[1], $info->[2], $info->[3]);
    }
  }
  return;
}

######################################################################
# Get the list of classes for a machine from RSVP.
#
# @param rsvp           The rsvp object to use
# @param hostname       The name of the host to check
#
# @return               The list of classes the host belongs to.
# @croaks               If no class info can be found for hostname.
##
sub getClassInfo {
  my ($self, $hostname) = assertNumArgs(2, @_);
  my $list = $self->listHosts(hostRegexp => $hostname,
                              verbose    => 1,
                             );
  foreach my $info (@{$list}) {
    if ($info->[0] eq $hostname) {
      if ($info->[2]) {
        return split(/,\s+/,$info->[2]);
      } else {
        return ();
      }
    }
  }
  croak("Unable to get class info for $hostname");
}

######################################################################
# Run an athinfo command on a given host
##
sub runAthinfo {
  my ($self, $host, $command) = assertNumArgs(3, @_);

  my $result = runSystemCommand("timeout 5m athinfo $host $command", 0);
  my @messages = split('\n', $result->{stdout});
  if (scalar(@messages) == 0) {
    if ($result->{stderr} ne "") {
      return ("FAILURE", "'athinfo $host $command': $result->{stderr}");
    } else {
      return ("FAILURE", "'athinfo $host $command' returned with no output");
    }
  }
  if ($messages[0] =~ m|unrecognized query|) {
    return ("FAILURE", "athinfod on $host doesn't support $command");
  }

  return @messages;
}

######################################################################
# Check the result of a rsvp request, croak if it failed.
##
sub _checkResult {
  my ($self, $result) = assertNumArgs(2, @_);
  if ($result->{type} eq "ERROR") {
    croak($result->{message});
  } elsif ($self->{verbose}) {
    print("$result->{message}\n");
  }
}

######################################################################
# Get the string representation of a structure
#
# @param struct         The structure to print
#
# @return the string rep of that structure
##
sub _toString {
  my $struct = shift;
  local $Data::Dumper::Purity = 1;
  local $Data::Dumper::Indent = 0;
  return Dumper($struct);
}

1;
