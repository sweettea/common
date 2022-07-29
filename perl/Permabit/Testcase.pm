##
# Testing framework base class
#
# @synopsis
#
#   package MyTest;
#   use Permabit::Assertions(assertEqualNumeric assertNumArgs);
#   use base qw(Permabit::Testcase);
#
#   our %PROPERTIES = (
#                      # Always save logs
#                      alwaysSaveLogs => 1,
#                     );
#
#   sub set_up {
#     my ($self) = assertNumArgs(1, @_);
#     $self->SUPER::set_up();
#     # Add additional setup if needed
#   }
#
#   sub tear_down {
#     my ($self) = assertNumArgs(1, @_);
#     # Add additional teardown if needed
#     $self->SUPER::tear_down();
#   }
#
#   sub testMyFunc {
#     my ($self) = assertNumArgs(1, @_);
#     assertEqualNumeric(1, myFunc());
#   }
#
#   1;
#
#
# @description
#
# C<Permabit::Testcase> provides a layer of utility methods and default
# configuration mechanisms on top of the C<Test::Unit::TestCase> base and
# the runtests.pl command.  All other testcases should extend this class.
#
# The primary advantage of Permabit::Testcase over its base class is
# support for running C<tear_down()> even if C<set_up()> failed.  The
# remaining functionality relates to setting test properties, either from
# the command line, on a per-file, or on a per-test basis.
#
# The default properties are loaded from the %PROPERTIES hashes in the
# testcase packages.  If method called properties_<testName> is defined, it
# will then be called.  It must return a hash whose values will override
# those in getProperties.
#
# $Id$
##
package Permabit::Testcase;

use strict;
use warnings FATAL => qw(all);
use Carp;
use Carp qw(confess);
use Class::Inspector;
use Data::Dumper;
use English qw(-no_match_vars);
use File::Basename;
use File::Copy;
use File::Path;
use List::Util qw(sum);
use Log::Log4perl;
use Log::Log4perl::Level;
use POSIX qw(strftime);
use Storable qw(dclone);
use Sys::Hostname;
use Time::HiRes qw(time);

use Permabit::Assertions qw(
  assertDefined
  assertMinArgs
  assertMinMaxArgs
  assertNumArgs
);
use Permabit::AsyncSub;
use Permabit::AsyncTasks;
use Permabit::ClassUtils qw(getClassHashKeys);
use Permabit::Constants;
use Permabit::Exception qw(SkipThisTest);
use Permabit::RSVPer;
use Permabit::SystemUtils qw(
  assertCommand
  assertSystem
  copyRemoteFilesAsRoot
  cp
  runCommand
  runQuietCommand
  scp
);
use Permabit::Utils qw(
  addToHash
  canonicalizeHostname
  getRandomSeed
  getUserName
  hashExtractor
  makeFullPath
  makeRandomToken
  mergeToHash
  sendChat
  shortenHostName
  waitForInput
);

use base qw(
  Test::Unit::TestCase
  Permabit::BinaryFinder
  Permabit::Propertied
);

# This is referenced directly from Permabit::TestRunner.
our $inTeardown = 0;

my $GET_CONSOLE_LOG_CMD
  = '/permabit/build/aws/lastrun/getCloudInstanceLog.py --stdout';

my $log = Log::Log4perl->get_logger(__PACKAGE__);

##
# @paramList{new}
our %PROPERTIES
  = (
     # @ple Should logfiles be saved even if the test passes?
     alwaysSaveLogs              => 0,
     # @ple An nfs accessible directory for binaries and other shared files.
     binaryDir                   => undef,
     # @ple Whether to send a jabber message on RSVP release failures
     chatFailures                => 1,
     # @ple The directory where stdout/stderr files are written.  This is
     #      set by runtests.pl.
     logDir                      => undef,
     # @ple The list of logfiles recorded for this testcase, including the name
     #      of the output file to which STDOUT and STDERR are being redirected
     #      and the names of the log files to which log4perl is logging.  This
     #      is set by runtests.pl.
     logFiles                    => [],
     # @ple Pause the test at these named manual wait points
     manualWaitPoint             => [],
     # @ple if a test can't clean up its machines, move them to maintenance
     moveToMaintenance           => 0,
     # @ple never save logs, nomatter what anybody says.
     neverSaveLogs               => 0,
     # @ple The top directory for nfs usage.  This is set by runtests.pl.
     nfsShareDir                 => undef,
     # @ple The date string that nightly set. This property stays undefined
     #      if nightly did not invoke this test.
     nightlyStart                => undef,
     # @ple XXX obsolete synonym for promptOnErrorBeforeTearDown.  Should
     #          use --manualWaitPoint=failure instead.
     poe                         => 0,
     # @ple XXX obsolete way to prompt the user before tearing down the
     #          test because of an error so that the user has time to
     #          inspect the machine.  Should use --manualWaitPoint=failure
     #          instead.
     promptOnErrorBeforeTearDown => 0,
     # @ple Ask rsvpd to randomize its list of available hosts before
     #      selecting.
     randomizeReservations       => 0,
     # @ple Run directory of commands
     runDir                      => undef,
     # @ple If logfiles are saved, the local directory to save them in.
     #      Defaults to the current directory.
     saveServerLogDir            => '.',
     # @ple The amount of time in seconds to allow for set_up (0 unlimited).
     setupTimeout                => 0,
     # @ple Whether to send output on RSVP release failures to the real
     #      stderr if stderr is being sent to a file
     stderrFailures              => 1,
     # @ple Suppress clean up of machines and just move them to maintenance
     suppressCleanup             => 0,
     # @ple Suppress clean up of the test machines if one of these named error
     #      types occurs.
     suppressCleanupOnError      => [],
     # @ple The "src" directory at the top of the tree.
     topDir                      => $main::DEFAULT_TOPDIR,
     # @ple The amount of time in seconds to allow for tear_down (0 unlimited).
     tearDownTimeout             => 0,
     # @ple The amount of time in seconds to allow for a testcase (0
     #       unlimited).
     testTimeout                 => 0,
     # @ple The RSVP types being used to reserve hosts.
     typeNames                   => [],
     # @ple The user that is running this test. This shouldn't be modified
     #      because it's not plumbed through to things such as RSVP or ssh.
     user                        => getUserName(),
     # @ple Whether or not to verify that any hosts provided on the command
     #      line (e.g. in clientNames or serverNames) are actually reserved
     #      and ready to be used.
     verifyReservations          => 1,
     # @ple The local dir to put temp files in. One is created for every
     #      machine used.
     workDir                     => undef,
     # @ple List of failure messages.
     _testFailed                 => [],
    );
##

###############################################################################
# Instantiate a new Testcase. Individual tests may provide parameters by
# using the %PROPERTIES hash.  This method should only be called by the
# Test::Unit framework.
#
# @param testName  The name of the test being created
# @params{new}
##
sub new {
  my $baseObj = shift;
  # @_ is set by the TestRunner to the name of the test being run
  my $testName = shift;
  my $seed = getRandomSeed();
  srand($seed);
  $log->debug("Permabit::Testcase->new($testName) (seed: $seed)");
  my $self = $baseObj->Test::Unit::TestCase::new($testName);

  $Carp::Verbose = 1; # force a backtrace on croak

  $self->{_fullName} = ref($self) . "::$testName";
  # make_test_from_coderef() uses Class::Inner to create tests, strip
  # off the dynamic class name it generates
  $self->{_fullName} =~ s|^Class::Inner::__A\d+::||;
  $self->{rsvpKey} = makeRandomToken(16);

  # Assemble the %PROPERTIES first, then copy them so that separate
  # instances of this class get their own instances of the anonymous lists
  # within it
  addToHash($self, %{$self->cloneClassHash("PROPERTIES")});

  # Set a workdir for subclasses that inherit directly from this class.
  # We have to do this after $self->{user} is set up.
  $self->{workDir} ||= "/u1/Testcase-$self->{user}/${PID}_"
                         . makeRandomToken(5) . "/";

  # Merge in test-method-specific properties
  my $propMethodName = $testName;
  if (($propMethodName =~ s/^(?:.*::)*test/properties/)
      && $self->can($propMethodName)) {
    mergeToHash($self, $self->$propMethodName());
  }

  # Expunge all options specified by runtests.pl
  map { delete($self->{$_}) } @Permabit::TestRunner::expungements;
  # Merge in command line options from hash passed in from
  # runtests.pl.  Clone it so that multiple tests in the same suite
  # can't interfere with one another.
  my %myRuntestOptions = %{ dclone(\%Permabit::TestRunner::testOptions) };
  mergeToHash($self, %myRuntestOptions);
  $self->_checkOptions(\%Permabit::TestRunner::testOptions);
  if ($self->{promptOnErrorBeforeTearDown} || $self->{poe}) {
    mergeToHash($self, manualWaitPoint => ["failure"]);
  }

  # Log the contents of $self
  my %tmp = %{$self};
  my $dumper = Data::Dumper->new([\%tmp], [qw(*self)]);
  $dumper->Purity(0)->Indent(2)->Sortkeys(1)->Quotekeys(0);
  $log->debug($dumper->Dump());

  my $envDumper = Data::Dumper->new([\%ENV], [qw(%ENV)]);
  $envDumper->Purity(0)->Indent(2)->Sortkeys(1)->Quotekeys(0);
  $log->debug($envDumper->Dump());

  return $self;
}

###############################################################################
# Set up the testcase configuration environment variable if the testcase has
# a specifice override file.
#
# The contents of the override file are applied after the loading of the
# general configuration file; either the system-level config or, if set, the
# file referenced in PERMABIT_PERL_CONFIG.
##
sub _set_up_testcase_configuration_override {
  my ($self) = assertNumArgs(1, @_);
  my $filename = Class::Inspector->loaded_filename(ref($self));
  # For dynamically created testcases there will be no file.
  # For such testcases that want to utilize overrides they must independently
  # specify such.
  if (defined($filename)) {
    $filename =~ s/pm$/yaml/;
    if (-e $filename) {
      if (!(-r $filename)) {
        confess("testcase override $filename is not readable");
      }
      $ENV{PERMABIT_PERL_TESTCASE_CONFIG_OVERRIDE} = $filename;
    }
  }
}

###############################################################################
# Set up for the test.  This can be overloaded to either add more
# functionality to the pre-test mechanism, or to disable the default
# mechanism.
##
sub set_up {
  my ($self) = assertNumArgs(1, @_);

  # Establish the testcase's configuration.
  $self->_set_up_testcase_configuration_override();

  # Make sure workDir exists so we can place temp files there
  mkpath($self->{workDir});
  $self->{runDir} = makeFullPath($self->{workDir}, 'run');
  # runtests.pl should set nfsShareDir for us (and will clean up afterwards)
  $self->{binaryDir} = makeFullPath($self->{nfsShareDir}, 'executables');
  mkpath($self->{binaryDir});

  # Copy a list of shared files into NFS where other machines can access them.
  my @sharedFiles = $self->listSharedFiles();
  my @sharedPaths
    = map { glob(makeFullPath($self->{topDir}, $_)) } @sharedFiles;
  if (scalar(@sharedPaths) > 0) {
    my $files = join(" ", @sharedPaths);
    assertSystem("rsync -a -L $files $self->{binaryDir}");
  }

  $self->logStateInKernLog("STARTING");
  foreach my $host ($self->getTestHosts()) {
    # Make sure runDir exists on each host.  A side effect of this is that
    # workDir exists on each host.
    assertCommand($host, "mkdir -p $self->{runDir}");
  }
}

###############################################################################
# Run the tail section.  This can be overloaded to perform post-test
# consistency checks.
##
sub run_coda {
  my ($self) = assertNumArgs(1, @_);

  my $notStarted = $self->getAsyncTasks()->countNotStarted();
  if ($notStarted > 0) {
    confess("$notStarted AsyncTasks were never started");
  }

  my $running = $self->getAsyncTasks()->countRunning();
  if ($running > 0) {
    confess("$running AsyncTasks are still running");
  }
}

###############################################################################
# Clean up after the test.  This must be overloaded if a subclass does
# set_up work that must be torn down
##
sub tear_down {
  my ($self) = assertNumArgs(1, @_);

  if (!$self->{suppressCleanup}) {
    # Stop any tasks belonging to this test.
    $self->tearDownAsyncTasks();
    # Stop all binaries found by the BinaryFinder running on any test hosts.
    my @binaries = $self->listBinaries();
    if (scalar(@binaries) > 0) {
      my $regexp = join("|", map { "^$_\$" } @binaries);
      foreach my $host ($self->getTestHosts()) {
        runCommand($host, "pkill -QUIT '$regexp'");
        runCommand($host, "pkill -KILL '$regexp'");
      }
    }
  }

  $self->saveAllLogFiles();

  if (!$self->{suppressCleanup}) {
    # Clean up the workDir on each host.  A side effect of this is that we
    # also clean up runDir.
    foreach my $host ($self->getTestHosts()) {
      runCommand($host, "rm -rf $self->{workDir}");
    }
    rmtree($self->{workDir});
  }
}

###############################################################################
# Skip this test, without registering it as a failing test.  This is intended
# to be called at any point in a set_up() method.
##
sub skipThisTest {
  my ($self) = assertNumArgs(1, @_);
  die(Permabit::Exception::SkipThisTest->new("skip"));
}

###############################################################################
# Get the hosts involved in test.  Overridden by subclasses.
#
# @return a list of hostnames
##
sub getTestHosts {
  my ($self) = assertNumArgs(1, @_);
  return ();
}

###############################################################################
# Get a list of executable files (and directories) to copy to an nfs
# accessible directory.  The paths must be relative to topDir.  Overridden
# by subclasses.
#
# @return the list of files to copy, relative to the top of the source tree.
##
sub listSharedFiles {
  my ($self) = assertNumArgs(1, @_);
  return ();
}

###############################################################################
# Get the configurable parameters for the testcase.  It derives the list of
# parameters by assembling the pieces that are used by the new() method.
#
# @return the parameter names that can be set on the runtests.pl command line.
##
sub getCommandLineOptions {
  my ($self) = assertNumArgs(1, @_);
  my %params = map { $_ => undef } (getClassHashKeys($self, 'PROPERTIES'),
                                    @{Permabit::RSVPer::getParameters()},);
  return grep { !/^_/ } keys(%params);
}

###############################################################################
# Verify that the options set are known.
#
# @param options        hashref with options
##
sub _checkOptions {
  my ($self, $options) = assertNumArgs(2, @_);
  my %params = map { $_ => undef } $self->getCommandLineOptions();
  my @badOptions = grep { !exists($params{$_}) } keys(%$options);
  if (@badOptions) {
    die("Bad options: " . join(" ", @badOptions) . "\n");
  }
}

###############################################################################
# Return the full name of this test, e.g. Testcase::SomeSuite::testFoo
##
sub fullName {
  my ($self) = assertNumArgs(1, @_);
  return $self->{_fullName};
}

###############################################################################
# @inherit
##
sub run {
  my ($self, $result, $runner) = @_;
  $self->{__PACKAGE__ . '_result'} = $result;
  return $self->SUPER::run($result, $runner);
}

###############################################################################
# Stop the currently running suite from running any more tests
##
sub stopSuite {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{__PACKAGE__ . '_result'}) {
    $self->{__PACKAGE__ . '_result'}->stop();
  }
}

###############################################################################
# Overload Test::Unit::TestCase::run_bare.  Run the test.  tear_down is
# ALWAYS called, even if set_up failed.  Can capture log files when
# individual tests fail.
##
sub run_bare {
  my ($self) = assertNumArgs(1, @_);
  $log->info("Running test on " . hostname());
  my $name = $self->{_fullName};
  my $doing = "STARTING";
  $log->info("STARTING $name");
  eval {
    $self->runMethod("set_up", $self->{setupTimeout});
    $self->manualWaitPoint("readyToRun", "Ready to run $name");
    $doing = "RUNNING";
    $log->info("$doing $name");
    $self->logStateInKernLog($doing);
    $self->runMethod("run_test", $self->{testTimeout});
    $doing = "CHECKING";
    $log->info("$doing $name");
    $self->logStateInKernLog($doing);
    $self->run_coda();
  };
  my $testError = $EVAL_ERROR;
  local $inTeardown = 1;
  my $deathMessage = undef;
  if (ref($testError)
      && $testError->isa("Permabit::Exception::SkipThisTest")) {
    # The code called the skipThisTest() method and we should treat this as a
    # successful test.
    $testError = undef;
  }
  if ($testError) {
    $self->setFailedTest("TEST FAILURE $doing $name : $testError");
    if (ref($testError) && $testError->isa("Permabit::Exception")) {
      my $typeList = $self->{suppressCleanupOnError};
      if (!defined($typeList)) {
      } elsif (ref($typeList)) {
        $self->{suppressCleanup}
          ||= grep { $testError->isa("Permabit::Exception::$_") } @$typeList;
      } elsif (defined($typeList)) {
        $self->{suppressCleanup}
          ||= $testError->isa("Permabit::Exception::$typeList");
      }
    }
    eval {
      $self->manualWaitPoint("failure", "Test $name failed");
      $log->info("CLEANUP $name");
      $self->logStateInKernLog("CLEANUP");
      $self->runMethod("tear_down", $self->{tearDownTimeout});
    };
    if ($EVAL_ERROR) {
      $log->fatal("CLEANUP FAILURE for FAILED $name: $EVAL_ERROR");
    }
    # throw the old error (just the top if it's a backtrace)
    $deathMessage = $testError =~ /^(.*?)\n(.*?)\n/ ? "$1\n$2" : $testError;
  } else {
    $log->info("FINISHED $name");
    $self->logStateInKernLog("FINISHED");
    my @fails = ();
    eval {
      $self->runMethod("tear_down", $self->{tearDownTimeout});
    };
    if ($EVAL_ERROR) {
      push(@fails, $EVAL_ERROR);
    }
    if ($self->failedTest()) {
      push(@fails, @{$self->{_testFailed}});
    }
    if (@fails) {
      $log->fatal("CLEANUP FAILURE for $name: $fails[0]");
      $deathMessage = join("\n", @fails);
    }
  }
  $self->logStateInKernLog("DONE");
  $self->getRSVPer()->closeRSVP($name);
  if (defined($deathMessage)) {
    die($deathMessage);
  }
  $log->info("DONE WITH $name");
  return 1;
}

###############################################################################
# Put a state marker in the kernel log of each host.  Allow this to fail on
# hosts that do not have the permatest package installed.
#
# @param state  The state of the test to log.
##
sub logStateInKernLog {
  my ($self, $state) = assertNumArgs(2, @_);
  my $mark = join(" ", "echo", $state, $self->fullName());
  my $printk = "sudo tee /sys/permatest/printk";
  map { runCommand($_, "$mark | $printk"); } ($self->getTestHosts());
}

###############################################################################
# Generate a test timeout signal handler that adjusts for the number of
# seconds slept waiting to get a reservation
#
# @param rsvper   the rsvper
# @param timeout  the amount of time to give the test, minus rsvp sleep,
#                 with 0 denoting no timeout
# @param context  context for error message
##
sub makeTimeoutHandler {
  my ($rsvper, $timeout, $context) = assertNumArgs(3, @_);

  if (!$timeout) {
    return 'DEFAULT';
  }
  $rsvper->clearSecondsSlept();
  my $startTime = time();
  my $handler = sub {
    my $elapsedTime = time() - $startTime;
    my $secondsSlept = $rsvper->getSecondsSlept();
    my $timeLeft = $timeout + $secondsSlept - $elapsedTime;
    $log->debug("ALRM: timeout=$timeout secondsSlept=$secondsSlept "
                . "elapsedTime=$elapsedTime");
    if ($timeLeft <= 0) {
      my $msg = $context . " TIMEOUT after $elapsedTime seconds";
      if ($secondsSlept) {
        $msg .= " ($secondsSlept seconds in RSVP wait)";
      }
      die($msg);
    } else {
      # alarm() truncates to integer, so pad a little, because
      # with Time::HiRes we're likely to be using a value just
      # slightly below an integer value.
      $timeLeft = int(0.5 + $timeLeft);
      $log->debug("Setting new alarm to $timeLeft");
      alarm($timeLeft);
    }
  };
  return $handler;
}

###############################################################################
# Run a method and die on timeout considering time slept by rsvp.
#
# @param methodName  the test method to run (setup, run_test, tear_down)
# @param timeout     the amount of time to give the test, minus rsvp sleep,
#                    with 0 denoting no timeout
##
sub runMethod {
  my ($self, $methodName, $timeout) = assertNumArgs(3, @_);

  my $rsvper = $self->getRSVPer();
  eval {
    local $SIG{ALRM} = makeTimeoutHandler($rsvper, $timeout, $methodName);
    alarm($timeout);
    $self->$methodName();
    alarm(0);
  };
  my $error = $EVAL_ERROR;
  my $slept = $rsvper->clearSecondsSlept();
  if ($slept) {
    $log->debug("$self->{_fullName} SLEPT $slept seconds waiting for RSVP");
  }
  if ($error) {
    die($error);
  }
}

###############################################################################
# We invert the Test::Unit filtering mechanism to allow us to run a
# specific test rather than filter out undesirable tests.  Return true
# if this test name does NOT match the given regexp (i.e., filter all
# methods that don't match the token).
##
sub filter_method {
  my ($self, $regexp) = assertNumArgs(2, @_);
  my $testcaseName = $self->{'Test::Unit::TestCase_name'};

  # Ignore filtering on the ALL regexp
  if ($testcaseName eq 'ALL') {
    return 0;
  } else {
    return $testcaseName !~ $regexp;
  }
}

###############################################################################
# Run some tear_down code and register a failure if the code dies.  This is
# done so that further cleanup can proceed.
#
# @param  code    Cleanup code
# @oparam prefix  Prefix to the error message
##
sub runTearDownStep {
  my ($self, $code, $prefix) = assertMinMaxArgs([""], 2, 3, @_);
  eval {
    $code->();
  };
  if ($EVAL_ERROR) {
    $self->manualWaitPoint("teardownFailure", "Test teardown step failed");
    $self->setFailedTest($prefix . $EVAL_ERROR);
  }
}

###############################################################################
# Tell this test that it has failed
#
# @param message  The failure message
##
sub setFailedTest {
  my ($self, $message) = assertNumArgs(2, @_);
  push(@{$self->{_testFailed}}, "setFailedTest: $message");
  $log->fatal($message);
}

###############################################################################
# Check whether or not the current test failed
#
# @return A true value if the current test failed, otherwise a false value.
##
sub failedTest {
  my ($self) = assertNumArgs(1, @_);
  return scalar(@{$self->{_testFailed}}) > 0;
}

###############################################################################
# Check whether or not this test should retrieve logfiles
#
# @return A true value if either failedTest() or alwaysSaveLogs is true.
##
sub shouldSaveLogs {
  my ($self) = assertNumArgs(1, @_);
  if ($self->{neverSaveLogs}) {
    return 0;
  }
  return $self->failedTest() || $self->{alwaysSaveLogs};
}

###############################################################################
# Returns the default path for where to save log file to.  Note that this
# method saves its result and returns the same value when called more than
# once for the same testcase.
#
# @return a path to a log file directory that might not exist yet.
##
sub getDefaultLogFileDirectory {
  my ($self) = assertNumArgs(1, @_);
  if (!defined($self->{_defaultLogFileDirectory})) {
    my $dirName = $self->{_fullName};
    $dirName =~ s|\s+|_|g;
    $self->{_defaultLogFileDirectory}
      = makeFullPath($self->{saveServerLogDir}, $dirName,
                     strftime("%Y-%m-%d_%H.%M.%S", localtime()));
    mkpath($self->{_defaultLogFileDirectory});
  }
  return $self->{_defaultLogFileDirectory};
}

###############################################################################
# If shouldSaveLogs() is true, save all log files generated by this
# test and place them in a given directory.  This will call
# saveLogFiles() with the directory to save logfiles into.  Explicitly
# passing a directory to save logfiles in is equivalent to having
# shouldSaveLogs() return true.
#
# @oparam saveDir       Directory to save the log files in.
##
sub saveAllLogFiles {
  my ($self, $saveDir) = assertMinMaxArgs(1, 2, @_);
  if ($self->shouldSaveLogs() || $saveDir) {
    local $EVAL_ERROR;
    if (!defined($saveDir)) {
      $saveDir = $self->getDefaultLogFileDirectory();
    }
    $log->debug("Saving log files to $saveDir");
    if (! -d $saveDir) {
      mkpath($saveDir);
    }
    eval {
      $self->saveLogFiles($saveDir)
    };
    if ($EVAL_ERROR) {
      $log->warn("Error saving log files: $EVAL_ERROR");
    }
    for my $logFile (@{$self->{logFiles}}) {
      my $destLogFile = makeFullPath($saveDir, basename($logFile));
      copy($logFile, $destLogFile)
        || $log->warn("Copy of $logFile to $destLogFile failed: $ERRNO");
    }
  }
}

###############################################################################
# Save logfiles generated by this test into the given directory.  This
# method should be overridden by subclasses to save their own logfiles.
# Any exceptions thrown by this method will be caught and logged.
#
# @param saveDir        The directory to save the logfiles into
##
sub saveLogFiles {
  my ($self, $saveDir) = assertNumArgs(2, @_);

  # Start saving /var/log and $sys->{runDir} from each test host.
  my @tasks;
  foreach my $host ($self->getTestHosts()) {
    my $hostDir = makeFullPath($saveDir, $host);
    mkpath($hostDir);
    my $s = sub {
      # Save the console, if we can; we don't care if it fails.
      runQuietCommand('localhost',
                      "$GET_CONSOLE_LOG_CMD $host > $hostDir/console");

      runCommand($host, "sudo journalctl --sync");
      copyRemoteFilesAsRoot($host, "/", "var/log/", $hostDir);
      if ($self->{runDir}) {
        runCommand($host, "sudo chmod a+r $self->{runDir}/*");
        scp("$host:$self->{runDir}/* $hostDir");
      }
    };
    my $t = {
             sub  => Permabit::AsyncSub->new(code => $s)->start(),
             host => $host,
            };
    push(@tasks, $t);
  }

  # Save any binaries and shared-objects that were used in the test.
  my $copiedSharedObjects = 0;
  foreach my $command ($self->listBinaries()) {
    my $binary = $self->findBinary($command);
    cp("$binary $saveDir");
    if (!$copiedSharedObjects && $binary =~ /albscan|albtest/) {
      my $dirname = dirname($binary);
      cp("$dirname/*.so* $saveDir");
      $copiedSharedObjects = 1;
    }
  }

  # Finish saving /var/log and $sys->{runDir} from each test host.
  foreach my $task (@tasks) {
    eval {
      $task->{sub}->result();
    };
    if ($EVAL_ERROR) {
      $log->warn("unable to save log files for $task->{host}: $EVAL_ERROR");
    }
  }
}

###############################################################################
# Utility method to reserve a given number of machines using default
# reservation time and message.
#
# @param count       The number of hosts to reserve
# @oparam class      The RSVP class from which to reserve any needed machines
# @oparam msg        Message for this allocation
#
# @return The list of hostnames that were reserved
##
sub reserveNumHosts {
  my ($self, $count, $class, $msg) = assertMinMaxArgs(2, 4, @_);
  my $rsvpMsg = $self->{rsvpMsg};
  if ($msg) {
    $rsvpMsg .= ': ' . $msg;
  }
  my $expire = 0;
  if ($self->{rsvpDuration}) {
    $expire = time() + $self->{rsvpDuration};
  }
  my $randomize = $self->{randomizeReservations} || 0;
  return $self->getRSVPer()->reserveHosts(numhosts  => $count,
                                          class     => $class,
                                          expire    => $expire,
                                          msg       => $rsvpMsg,
                                          randomize => $randomize,
                                          wait      => 1);
}

###############################################################################
# Utility method to reserve a group of machines with default reservation
# time and message.  If hosts were provided on the command line, they will
# be used preferentially, in order.
#
# @param type  the type of machine to reserve.  This text string is used
#              to build the name of 4 fields in $self:
#
#              typeClass  The RSVP class from which to reserve any needed
#                         machines
#
#              typeLabel  A suffix added to the RSVP message that generally
#                         identifies how the machine is used
#
#              typeNames  IN:   The host names from the command line
#                         OUT:  The host names that are to be used
#
#              numTypes   The number of machines needed
##
sub reserveHostGroup {
  my ($self, $type) = assertNumArgs(2, @_);
  my $numTypes = $self->{"num" . ucfirst(${type}) . "s"};
  my $typeNames = "${type}Names";
  my $givenNames = $self->canonicalizeHostnames($self->{$typeNames});
  $self->{$typeNames} = [@$givenNames];
  my @hostNames;
  my @tasks;
  while (($numTypes > 0) && (scalar(@$givenNames) > 0)) {
    my $host = shift(@$givenNames);
    if ($self->{verifyReservations}) {
      my $sub = sub { $self->getRSVPer()->verifyReservation($host); };
      my $task = Permabit::AsyncSub->new(code => $sub);
      $task->start();
      push(@tasks, $task);
    }
    push(@hostNames, $host);
    --$numTypes;
  }
  if ($numTypes > 0) {
    push(@hostNames,
         $self->reserveNumHosts($numTypes, $self->{"${type}Class"},
                                $self->_mapTypeToLabel($type)));
  }
  map { $_->result() } @tasks;
  $self->{$typeNames} = [@hostNames];
}

###############################################################################
# Utility method to reserve multiple groups of machines with default
# reservation time and message.  It is equivalent to using the
# reserveHostGroup method for each group, but with the optimization of
# using a single RSVP reserve request when possible.
#
# @param types  the types of machine to reserve.
##
sub reserveHostGroups {
  my ($self, @types) = assertMinArgs(2, @_);
  # For each type determine how many hosts are needed
  my (%class, %had, %names, %need, %want);
  for my $type (@types) {
    my $numTypes = "num" . ucfirst(${type}) . "s";
    $names{$type} = $self->canonicalizeHostnames($self->{"${type}Names"});
    $class{$type} = $self->{"${type}Class"} || "";
    $had{$type} = scalar(@{$names{$type}});
    $want{$type} = $self->{$numTypes};
    $need{$type} = $want{$type} - $had{$type};

    if (!grep { /^$type$/ } @{$self->{typeNames}}) {
      push(@{$self->{typeNames}}, $type);
    }
  }
  # Process types that do not need any hosts reserved.  We call
  # reserveHostGroup for the side effect of verifying reservations.
  map { $self->reserveHostGroup($_) } grep { $need{$_} <= 0 } @types;
  @types = grep { $need{$_} > 0 } @types;
  # Now reserve the hosts, grouping like RSVP classes together.
  while (scalar(@types) > 0) {
    my $selectedClass = $class{$types[0]};
    my @selectedTypes = grep { $class{$_} eq $selectedClass } @types;
    @types = grep { $class{$_} ne $selectedClass } @types;
    if (scalar(@selectedTypes) == 1) {
      # Only one host group needs this RSVP class
      $self->reserveHostGroup(@selectedTypes);
    } else {
      # Multiple host groups need this RSVP class.  Fabricate a "joint" type
      # and use it to reserve all the machines in a single RSVP request.
      my @labels = map { $self->_mapTypeToLabel($_) } @selectedTypes;
      local $self->{jointClass} = $selectedClass;
      local $self->{jointLabel} = join(" or ", @labels);
      local $self->{jointNames} = [map { @{$names{$_}} } @selectedTypes];
      local $self->{numJoints} = sum(map { $want{$_} } @selectedTypes);
      $self->reserveHostGroup("joint");
      my @hosts =  @{$self->{jointNames}};
      for my $type (@selectedTypes) {
        $self->{"${type}Names"} = [splice(@hosts, 0, $had{$type})];
      }
      for my $type (@selectedTypes) {
        push(@{$self->{"${type}Names"}}, splice(@hosts, 0, $need{$type}));
      }
    }
  }
}

###############################################################################
# Find the suffix to apply to the RSVP reservation message for the
# specified type of host.
#
# @param  type  The type of machine being reserved
#
# @return the suffix to apply to the RSVP message.  The triage process
#         makes use of this suffix when creating JIRA tickets.
##
sub _mapTypeToLabel {
  my ($self, $type) = assertNumArgs(2, @_);
  my $typeLabel = "${type}Label";
  return (exists($self->{$typeLabel}) && $self->{$typeLabel}) || $type;
}

###############################################################################
# Use for manual testing.  Called at a named point where the test can
# pause waiting for a user response.  The test will pause if it is
# invoked with --manualWaitPoint=NAME.
#
# @param name     Name of the manual wait point
# @param message  Message to print out when pausing.
##
sub manualWaitPoint {
  my ($self, $name, $message) = assertMinMaxArgs(2, 3, @_);
  if (!defined($self->{manualWaitPoint})) {
    $self->{manualWaitPoint} = [];
  }
  if (!ref($self->{manualWaitPoint})) {
    $self->{manualWaitPoint} = [$self->{manualWaitPoint}];
  }
  if (grep { $_ eq $name } @{$self->{manualWaitPoint}}) {
    $message ||= "Hit return to cause this test to continue-->";
    my $msg = "Manual wait point $name triggered: $message";
    $log->info($msg);
    sendChat(undef, $ENV{LOGNAME}, "alert", $msg);
    waitForInput($msg);
  }
}

###############################################################################
# Utility method to canonicalize all hostnames in the given listref.
#
# @param  hostnames The listref of hostnames to be canonicalized
# @oparam shorten   whether the hostname should be shortened as well;
#                   what hostnames can be (and how they are) shortened is
#                   controlled by the implementation of Utils::shortenHostName.
#
# @return The list of hostnames in canonical form
##
sub canonicalizeHostnames {
  my ($self, $hostnames, $shorten) = assertMinMaxArgs([1], 2, 3, @_);
  if (!defined($hostnames)) {
    $hostnames = [];
  }
  # Convert this to an arrayref if it isn't one already (ie, one host
  # given on the command line)
  if (!ref($hostnames)) {
    $hostnames = [split(/,/, $hostnames)];
  }
  my @canonList
    = map {canonicalizeHostname($_)} @{$hostnames};
  if ($shorten) {
    @canonList = map {shortenHostName($_)} @canonList;
  }
  return \@canonList;
}

###############################################################################
# Assert deep inequality of two lists/hashes.
#
# @param this         reference to first thing to compare
# @param that         reference to second thing to compare
# @param errorMessage error message to throw
##
sub assert_deep_not_equals {
  my ($self, $this, $that, $errorMessage) = assertMinMaxArgs(3, 4, @_);

  eval {
    $self->assert_deep_equals($this, $that, $errorMessage);
  };

  if (!$EVAL_ERROR) {
    confess("assert_deep_not_equals failed: Both lists were equal\n");
  }
}

###############################################################################
# Get the RSVPer object for this TestCase
#
# @return the rsvper object
##
sub getRSVPer {
  my ($self) = assertNumArgs(1, @_);
  $self->{rsvper}
    ||= Permabit::RSVPer->new(
          hashExtractor($self, Permabit::RSVPer::getParameters())
        );
  return $self->{rsvper};
}

###############################################################################
# Return a dummy testcase that will never be run.  The testcase will
# contain all the test parameters of a real test, including the ones
# specified as command line options.  A suite() method can use this dummy
# testcase to alter how it builds the test suite.
#
# @return the dummy test case
##
sub makeDummyTest {
  my ($package) = assertNumArgs(1, @_);
  # The test name "doNotRun" is known to the triage scripts.
  return $package->make_test_from_coderef(sub { die("do not run this"); },
                                          "${package}::doNotRun");
}

###############################################################################
# Get the list of tasks belonging to this test.
#
# @return the Permabit::AsyncTasks listing all the tasks
##
sub getAsyncTasks {
  my ($self) = assertNumArgs(1, @_);
  $self->{_asyncTasks} //= Permabit::AsyncTasks->new();
  return $self->{_asyncTasks};
}

###############################################################################
# Stop all tasks belonging to this test.
##
sub tearDownAsyncTasks {
  my ($self) = assertNumArgs(1, @_);
  $self->runTearDownStep(sub { $self->getAsyncTasks()->kill(); });
  delete($self->{_asyncTasks});
}

1;
