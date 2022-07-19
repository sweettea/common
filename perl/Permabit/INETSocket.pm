#############################################################################
# A derivative of IO::Socket::INET that sets the maximum TCP SYN count to 8.
# This gives us more tries at connecting to a busy server before the connection
# attempt gives up.
#
# @synopsis
#
# use Permabit::INETSocket;
# my $socket = Permabit::INETSocket->new(Proto       => 'tcp',
#                                        PeerAddr    => $host,
#                                        PeerPort    => $port);
# if (!$socket) {
#   croak("Failed to connect to $host:$port\n");
# }
#
# @description
#
# C<Permabit::INETSocket> is a wrapper for IO::SOCKET::INET which sets
# the TCP SYN count socket option to 8.
#
# $Id$
##
package Permabit::INETSocket;

use Carp;
use English;
use Log::Log4perl;
use Socket qw(IPPROTO_TCP);
use strict;
use warnings;

use base qw(IO::Socket::INET);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

# Magic constant! This is the TCP SYN count option number.
# This is taken from the Linux system headers, but the standard Perl
# socket modules don't know about it.
my $TCP_SYNCNT = 7;

# At 8 attempts, the total timeout period appears to be over three
# minutes and the SYN retransmission interval is nearly a minute, so
# we probably don't want to drag it out much longer.
my $MAX_SYN_COUNT = 8;

######################################################################
# Create a new socket.
#
# @inherit
##
sub new {
  my $class = shift(@_);
  return $class->SUPER::new(@_);
}

######################################################################
# Override the base class connect() method to give us a hook between
# socket creation and connection time so that we can set options
# affecting the connection process.
##
sub connect {
  my $socket = shift(@_);
  if (!$socket->setsockopt(IPPROTO_TCP, $TCP_SYNCNT, $MAX_SYN_COUNT)) {
    $log->debug("setsockopt failed $ERRNO");
  }
  return $socket->SUPER::connect(@_);
}

1;
