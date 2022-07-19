##
# Test Tempfile
#
# $Id$
##
package testcases::Tempfile_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use File::Temp;
use Log::Log4perl;
use Permabit::Tempfile;
use Permabit::Assertions qw(
  assertFileDoesNotExist
  assertFileExists
  assertNumArgs
  assertTrue
);
use Permabit::AsyncSub;

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

sub testSimple {
  my ($self) = assertNumArgs(1, @_);

  my $tf = Permabit::Tempfile->new(SUFFIX => '.tempfile_t1');
  my $filename = $tf->filename();
  assertFileExists($filename);
  $tf = undef;
  assertFileDoesNotExist($filename);
}

sub testAsyncSub {
  my ($self) = assertNumArgs(1, @_);

  my $tf = Permabit::Tempfile->new(SUFFIX => '.tempfile_t1');
  my $filename = $tf->filename();
  assertFileExists($filename);
  my $sub = sub {
    $tf = undef;
  };
  Permabit::AsyncSub->new(code => $sub)->start()->result();
  assertFileExists($filename);
  $tf = undef;
  assertFileDoesNotExist($filename);
}

1;
