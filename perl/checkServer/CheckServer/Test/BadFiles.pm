##
# Check if various bad files exist.
#
# $Id$
##
package CheckServer::Test::BadFiles;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use CheckServer::Constants qw(
  @BAD_FILES
  %testModules
);

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  foreach my $glob (@BAD_FILES) {
    $self->checkFile($glob);
  }

  if (!$self->isAlbireo()) {
    return;
  }

  my $kernel = $self->kernel();
  my $lsmodResult = $self->runCommand('lsmod');
  foreach my $module (keys(%testModules)) {
    $self->checkFile("/lib/modules/$kernel/kernel/drivers/block/$module.ko");
    $self->checkFile("/lib/modules/$kernel/updates/dkms/$module.ko");
  }
}

########################################################################
# Check for the non-existance of a specific file or matching a glob
#
# @param fileOrGlob  The file or glob to check
##
sub checkFile {
  my ($self, $fileOrGlob) = assertNumArgs(2, @_);
  if ($fileOrGlob =~ /[\*\?]/) {
    foreach my $file (glob($fileOrGlob)) {
      $self->fail("$file exists matching $fileOrGlob");
      $self->addFixes("rm -f $file");
    }
  } elsif (-f $fileOrGlob) {
    $self->fail("$fileOrGlob exists");
    $self->addFixes("rm -f $fileOrGlob");
  }
}

1;

