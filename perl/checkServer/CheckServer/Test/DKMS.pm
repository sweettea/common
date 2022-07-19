##
# Check that there are no dkms packages installed
#
# $Id$
##
package CheckServer::Test::DKMS;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use CheckServer::Constants;

use base qw(CheckServer::AsyncTest);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  foreach my $moduleName (keys(%testModules)) {
    $self->checkDKMSStatus($moduleName);
    $self->checkModinfo($moduleName);
    $self->checkSources($moduleName);
  }
}

######################################################################
# Check that dkms status for a module.
#
# @param module  The name of the module to check
##
sub checkDKMSStatus {
  my ($self, $module) = assertNumArgs(2, @_);
  foreach my $line ($self->assertCommand("dkms status -m $module 2>&1")) {
    if ($line !~ /^$module,\s*(\S+)[,:]/) {
      $self->fail("dkms output unexpected: $line");
      next;
    }
    $self->fail("found $module DKMS package ($1)");
    $self->addFixes("dkms remove -m $module -v $1 --all");
  }
}

######################################################################
# Sometimes DKMS fails to completely clean up the module.
#
# @param module  The name of the module to check
##
sub checkModinfo {
  my ($self, $module) = assertNumArgs(2, @_);
  # If modinfo exits with a non-zero status then that means vdo isn't
  # installed.
  foreach my $line ($self->runCommand("modinfo $module")) {
    if ($line =~ /^filename:\s+(\S+)/) {
      $self->fail("found $module installed ($1)");
      $self->addFixes("rm -f $1 && depmod");
    }
  }
}

######################################################################
# Make sure we haven't left unpacked sources lying around, including older
# versions.
#
# @param module  The name of the module to check
##
sub checkSources {
  my ($self, $module) = assertNumArgs(2, @_);
  foreach my $dir (grep({ -d $_ } glob("/usr/src/$module-*"))) {
    $self->fail("$dir exists");
    $self->addFixes("rm -rf $dir");
  }
}

1;
