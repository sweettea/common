##
# Check for kernel modules.
#
# $Id$
##
package CheckServer::Test::Modules;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use File::Basename;
use Log::Log4perl;

use Permabit::Assertions qw(assertNumArgs);

use CheckServer::Constants qw(%testModules);

use base qw(CheckServer::Test);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

########################################################################
# @inherit
##
sub skip {
  my ($self) = assertNumArgs(1, @_);

  return !$self->isAlbireo();
}

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);

  $self->checkLsmod();

  if (-f '/etc/modules') {
    eval($self->checkEtcModules());
  }

  if (-d '/etc/modules-load.d') {
    eval($self->checkEtcModulesLoadD());
  }
}

########################################################################
# lsmod lists the active kernel modules in the correct order for them to be
# removed. In particular, "albireo" will be listed after "kvdo" and/or
# "zubenelgenubi".
##
sub checkLsmod {
  my ($self) = assertNumArgs(1, @_);

  foreach my $module (grep({ exists($testModules{$_}) }
                           map({ m/^(\S+)\s+\d+/ }
                               $self->runCommand('lsmod')))) {
    $self->fail("FOUND module $module");
    $self->addFixes("sudo rmmod $module");
  }
}

########################################################################
# Check for test modules listed in /etc/modules.
##
sub checkEtcModules {
  my ($self) = assertNumArgs(1, @_);
  foreach my $module (grep({ chomp($_);
                             exists($testModules{$_})
                           } $self->openOrAbort('/etc/modules')->getlines())) {
    $self->fail("FOUND module $module in startup list");
    $self->addFixes("sed -i /^$module/d /etc/modules");
  }
}

########################################################################
# Check for test modules listed in /etc/modules-load.d.
##
sub checkEtcModulesLoadD {
  my ($self) = assertNumArgs(1, @_);
  my $dir = $self->openDirOrAbort('/etc/modules-load.d');
  foreach my $file ($dir->read()) {
    if (($file =~ /^(.*)\.conf$/) && exists($testModules{$1})) {
      $self->fail("FOUND module $1 in startup list");
      $self->addFixes("rm /etc/modules-load.d/$file");
    }
  }
}

1;
