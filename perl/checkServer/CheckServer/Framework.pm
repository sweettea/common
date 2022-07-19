##
# The checkServer.pl test runner.
#
# $Id$
##
package CheckServer::Framework;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use Log::Log4perl;

use Class::Inspector;
use File::Basename;
use File::Spec;
use FindBin;
use IO::Dir;
use IO::File;

use Permabit::Assertions qw(
  assertMinArgs
  assertNumArgs
);
use Permabit::RSVP;
use Permabit::Utils qw(
  makeFullPath
);

use CheckServer::Constants;
use CheckServer::Host;

use base qw(CheckServer::Delegator);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my $DEFAULT_TEST_DIR = 'Test';

########################################################################
# Create a CheckServer::Framework.
##
sub new {
  my ($pkg, %config) = assertMinArgs(1, @_);
  my $self = $pkg->SUPER::new(CheckServer::Host->new(),
                              asyncTests => [],
                              syncTests  => [],
                              reboot     => 0,
                              %config);


  my %path = map { ($_, 1) } split(':', $ENV{PATH});
  $ENV{PATH} = join(':',
                    grep({ !exists($path{$_}) }
                         @{$self->getParameter('paths', [])}),
                    $ENV{PATH});

  $self->{testRegexp} //= '.*';
  $self->loadTests();
  return $self;
}

########################################################################
# Load the test modules.
##
sub loadTests {
  my ($self)  = assertNumArgs(1, @_);

  my $testDirs = $self->getParameter('testDirs', {});
  foreach my $dir (keys(%{$testDirs})) {
    $log->debug("dir: $dir");
    # If the test dir is relative, interpret it as relative to checkServer.pl.
    my $path = (File::Spec->file_name_is_absolute($dir)
                ? $dir
                : makeFullPath($FindBin::RealBin, $dir));
    foreach my $test (glob("$path/*.pm")) {
      $self->loadTest($test, $testDirs->{$dir});
    }
  }

  $log->debug("built test list");
}

########################################################################
# Load a test module
#
# @param file         The file to load
# @param classPrefix  The prefix of the class defined by the module
##
sub loadTest {
  my ($self, $file, $classPrefix) = assertNumArgs(3, @_);
  my $class = basename($file);
  $class =~ s/\.pm$//;
  $class = join('::', $classPrefix, $class);
  if ($class !~ $self->{testRegexp}) {
    $log->debug("skipping $class due to testRegexp");
    return;
  }
  $log->info("loading $class from $file");
  eval("require '$file'; import $class");
  if ($EVAL_ERROR) {
    die($EVAL_ERROR);
  }

  $class->new($self);
}

########################################################################
# Add a synchronous test.
##
sub addTest {
  my ($self, $test) = assertNumArgs(2, @_);
  if ($test->{async}) {
    push(@{$self->{asyncTests}}, $test);
  } else {
    push(@{$self->{syncTests}}, $test);
  }
}

########################################################################
# Run the tests.
##
sub run {
  my ($self) = assertNumArgs(1, @_);
  $self->{tests} = [grep({ $self->shouldRun($_) }
                         @{$self->{asyncTests}}, @{$self->{syncTests}})];
  foreach my $test (@{$self->{tests}}) {
    $log->info($test->{async} ? "async: $test" : $test);
    if (!$self->{noRun}) {
        $test->run();
    }
  }

  if (!$self->{noRun}) {
    foreach my $test (@{$self->{tests}}) {
      $test->wait();
    }
  }

  if (!$self->fix() && !$self->report()) {
    print "success\n";
  }
}

######################################################################
# Check whether a test should be run.
##
sub shouldRun {
  my ($self, $test) = assertNumArgs(2, @_);
  if ($test->skip()) {
    $log->info("skipping $test");
    return 0;
  }

  return 1;
}

########################################################################
# Perform any fixes if we have been told to do so.
#
# @return True if there was anything to fix
##
sub fix {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{fix}) {
    if (!$self->{force}) {
      eval {
        my $rsvp = Permabit::RSVP->new();
        $rsvp->verify(host => $self->hostname(),
                      user => ($self->{user} || $ENV{SUDO_USER}
                               || $ENV{USER}));
      };
      if ($EVAL_ERROR) {
        print STDERR "rsvp: $EVAL_ERROR";
      }
    }
  } elsif (!$self->{dryRun}) {
    return 0;
  }

  my $fixed = 0;
  foreach my $test (@{$self->{tests}}) {
    if ($self->{verbose} || $self->{debug}) {
      $test->report();
    }


    $fixed += $test->fix($self->{dryRun});
  }

  if ($self->{reboot}) {
    $fixed++;
    print STDERR "We would like to suggest rebooting\n";
  }

  return $fixed;
}

########################################################################
# Report any failures.
#
# @return True if there were any
##
sub report {
  my ($self) = assertNumArgs(1, @_);
  my $failures = 0;
  foreach my $test (@{$self->{tests}}) {
    if ($test->passed()) {
      next;
    }

    if ($failures == 0) {
      $failures++;
      $log->warn("FAILURE");
    }

    $test->report();
  }

  return $failures;
}

########################################################################
# Note that a reboot is in order.
##
sub suggestReboot {
  my ($self) = assertNumArgs(1, @_);
  $self->{reboot} = 1;
}

########################################################################
sub load {
  my ($self, $method, $install) = assertNumArgs(3, @_);
  if (exists($self->{$method})) {
    no strict 'refs';
    *{$install} = sub {
      my ($self) = assertNumArgs(1, @_);
      return $self->{$method};
    };

    return 1;
  }

  return $self->SUPER::load($method, $install);
}

1;
