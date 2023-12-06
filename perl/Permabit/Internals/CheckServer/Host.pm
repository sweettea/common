package Permabit::Internals::CheckServer::Host;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Configured;
use Permabit::Assertions qw(
  assertNumArgs
);

use base qw(Exporter Permabit::Configured);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

our @EXPORT = qw(
  getPermabitMounts
);

sub getPermabitMounts {
  my ($self) = assertNumArgs(1, @_);
  return %{$self->{permabitMounts}};
}

1;
