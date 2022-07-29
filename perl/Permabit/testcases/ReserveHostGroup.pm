##
# Test reserving host groups
#
# $Id$
##
package testcases::ReserveHostGroup;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(
  assertEq
  assertEqualNumeric
  assertGENumeric
  assertMinArgs
  assertNotDefined
  assertNumArgs
);
use Permabit::RSVPer;

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

###########################################################################
##
sub testReserveHostGroup {
  my ($self) = assertNumArgs(1, @_);

  # Reserve a client host group
  $self->{clientClass} = "ALL";
  $self->{clientNames} = undef;
  $self->{numClients} = 1;
  $self->reserveHostGroup("client");
  assertEqualNumeric(1, $self->{numClients});
  assertEqualNumeric(1, scalar(@{$self->{clientNames}}));

  # Reserve a server host group
  $self->{serverClass} = "ALL";
  $self->{serverNames} = undef;
  $self->{numServers} = 1;
  $self->reserveHostGroup("server");
  assertEqualNumeric(1, $self->{numClients});
  assertEqualNumeric(1, scalar(@{$self->{clientNames}}));
  assertEqualNumeric(1, $self->{numServers});
  assertEqualNumeric(1, scalar(@{$self->{serverNames}}));
}

###########################################################################
##
sub testReserveHostGroups {
  my ($self) = assertNumArgs(1, @_);

  # Reserve a client and a server host group
  $self->{clientClass} = "ALL";
  $self->{clientNames} = undef;
  $self->{numClients} = 1;
  $self->{serverClass} = "ALL";
  $self->{serverNames} = undef;
  $self->{numServers} = 1;
  $self->reserveHostGroups("client", "server");
  assertEqualNumeric(1, $self->{numClients});
  assertEqualNumeric(1, scalar(@{$self->{clientNames}}));
  assertEqualNumeric(1, $self->{numServers});
  assertEqualNumeric(1, scalar(@{$self->{serverNames}}));
  # We should have a total of 2 hosts
  my @single = (@{$self->{clientNames}}, @{$self->{serverNames}});
  my %singleMap = map { $_ => undef } @single;
  assertEqualNumeric(2, scalar(keys(%singleMap)));

  # Reserve larger host groups.
  my @clients = @{$self->{clientNames}};
  my @servers = @{$self->{serverNames}};
  $self->{numClients} = 2;
  $self->{numServers} = 2;
  $self->reserveHostGroups("client", "server");
  assertEqualNumeric(2, $self->{numClients});
  assertEqualNumeric(2, scalar(@{$self->{clientNames}}));
  assertEqualNumeric(2, $self->{numServers});
  assertEqualNumeric(2, scalar(@{$self->{serverNames}}));
  # The first host in each group should not change.
  assertEq($clients[0], $self->{clientNames}[0]);
  assertEq($servers[0], $self->{serverNames}[0]);
  # We should have a total of 4 hosts.
  my @double = (@{$self->{clientNames}}, @{$self->{serverNames}});
  my %doubleMap = map { $_ => undef } @double;
  assertEqualNumeric(4, scalar(keys(%doubleMap)));
}

###########################################################################
# Select from the input class list those that have associated hosts.
#
# @param classList  List of classes to iterate through
# @return List of classes with hosts.
##
sub selectClassesWithHosts {
  my ($self, @classList) = assertMinArgs(2, @_);
  my $rsvp = $self->getRSVPer()->_getRSVP();

  return (grep { scalar($rsvp->listHosts(class => $_)) >= 2 } @classList);
}

###########################################################################
# Return a list of the hosts reserved.
#
# @return List of hostnames reserved
##
sub getReservedHosts {
  my ($self) = assertNumArgs(1, @_);
  my @reservedHosts = ();

  push(@reservedHosts, map { @{$self->{$_ . "Names"}} } @{$self->{typeNames}});

  return @reservedHosts;
}

###########################################################################
# Return a hash of types and associated hosts reserved.
#
# @return Hashref of types with reserved count and hostnames
##
sub getReservedTypesAndHosts {
  my ($self) = assertNumArgs(1, @_);
  my %reserved;
  for my $type (@{$self->{typeNames}}) {
    $reserved{$type} = {
      'count' => $self->{"num" . ucfirst(${type}) . "s"},
      'hosts' => $self->{"${type}Names"},
    };
  }

  return \%reserved;
}

###########################################################################
# Verify the new reservation counts and classes match the expected.
#
# @param expected  Hashref of expected OS classes and counts
##
sub verifyReservations {
  my ($self, $expected) = assertNumArgs(2, @_);
  my $reserved = $self->getReservedTypesAndHosts();

  foreach my $class (keys(%{$expected})) {
    my $type = lc($class);
    my $expectedCount = $expected->{$class};
    my $count = $reserved->{$type}{count};
    my $numHosts = scalar(@{$reserved->{$type}{hosts}});

    assertEqualNumeric($expectedCount, $count, "Expected newly reserved count"
                       . " of $expectedCount for class $class, but have count"
                       . " of $count");
    assertEqualNumeric($expectedCount, $numHosts, "Expected $expectedCount new"
                       . " host reservations for class $class, but have"
                       . " $numHosts");
  }

  my $rsvper = $self->getRSVPer();
  foreach my $class (keys(%{$expected})) {
    foreach my $client (@{$reserved->{lc($class)}{hosts}}) {
      $log->debug("Checking that host $client is class $class");
      my $actualClass = $rsvper->getOSClass($client);
      assertEq($class, $actualClass, "Expected class $class"
               . " for host $client, but got class $actualClass");
    }
  }
}

###########################################################################
# Reserve the necessary OS class hosts and verify against expected.
#
# @param needed         Hashref of needed OS classes and host counts
# @param expectedTotal  Total number of reserved hosts expected
##
sub reserveHostsAndVerify {
  my ($self, $needed, $expectedTotal) = assertNumArgs(3, @_);

  $self->{clientNames} = [$self->getReservedHosts()];
  my $reservedCount = scalar(@{$self->{clientNames}});

  $self->reserveHostGroupsByOSClass($needed);
  $self->verifyReservations($needed);

  my @clients = $self->getReservedHosts();
  my $totalCount = scalar(@clients);

  assertEqualNumeric($expectedTotal, $totalCount, "Expected a current host"
                     . " total of $expectedTotal, but have $totalCount");
}

###########################################################################
##
sub testReserveHostGroupsByOSClass {
  my ($self) = assertNumArgs(1, @_);

  assertNotDefined($self->{numClients});
  assertNotDefined($self->{clientNames});
  assertNotDefined($self->{numServers});
  assertNotDefined($self->{serverNames});

  # Three RSVP OS classes will be used in this test - generate the list of the
  # latest RHEL and two most recent FEDORA OS classes that have hosts associated
  # with them
  my $rsvp = $self->getRSVPer()->_getRSVP();
  my @OS_CLASSES = $rsvp->listOsClasses();
  my @rhel = grep { $_ =~ /^RHEL\d+$/ } @OS_CLASSES;
  my @fedora = grep { $_ =~ /^FEDORA\d+$/ } @OS_CLASSES;

  @rhel = $self->selectClassesWithHosts(@rhel);
  @fedora = $self->selectClassesWithHosts(@fedora);

  my $numClasses = scalar(@rhel);
  assertGENumeric($numClasses, 1, "Must have at least one RHEL version"
                  . " included in test, but have $numClasses");
  $numClasses = scalar(@fedora);
  assertGENumeric($numClasses, 2, "Must have at least two FEDORA versions"
                  . " included in test, but have $numClasses");
  my @testClasses = (pop(@rhel), $fedora[-2], $fedora[-1]);

  # Reserve a client from a single RSVP OS class
  $self->{clientClass} = 'ALL';
  my $classes = { $testClasses[0] => 1 };
  $self->reserveHostsAndVerify($classes, 1);

  # Reserve multiple clients from a single RSVP OS class
  $classes = { $testClasses[1] => 2 };
  $self->reserveHostsAndVerify($classes, 3);

  # Reserve clients from multiple RSVP OS classes
  $classes = { $testClasses[0] => 2,
               $testClasses[2] => 1,
             };
  $self->reserveHostsAndVerify($classes, 5);

  # Reserve RSVP OS classes that already have reserved hosts - no new hosts
  # should be reserved
  $classes = { $testClasses[0] => 2,
               $testClasses[1] => 2,
               $testClasses[2] => 1,
             };
  $self->reserveHostsAndVerify($classes, 5);

  my $previousHosts = join(",", sort(@{$self->{clientNames}}));
  my $currentHosts = join(",", sort($self->getReservedHosts()));
  assertEq($previousHosts, $currentHosts, "Expected the list of previous hosts"
           . "($previousHosts) to match the current hosts ($currentHosts)");
}

1;
