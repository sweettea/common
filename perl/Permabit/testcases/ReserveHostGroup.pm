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

1;
