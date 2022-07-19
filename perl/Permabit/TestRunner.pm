##
# Script to run tests derived from Permabit::Testcase
#
# @synopsis
#
# runtests.pl --baseTestClass=I<BASECLASS>
#             --suiteFile=I<FILE>
#             [--config=I<FILE>]
#             [--copySharedFiles]
#             [--exclude=<test>[,...]]
#             [--excludeRegexp=<REGEXP>]
#             [--excludeSuites=<suite>[,...]]
#             [--expunge=<option>[,...]]
#             [--help]
#             [--JSON]
#             [--log=1]
#             [--logDir=I<DIR>]
#             [--moveToMaintenance]
#             [--noRun=1]
#             [--promptOnErrorBeforeTearDown=1]
#             [--quiet=1]
#             [--repeat[=<COUNT>]]
#             [--sendChat]
#             [--testRegexp=I<REGEXP>]
#             [--threads=I<COUNT>]
#             [--scale[=<RSVP-CLASS>]]
#             [--symbols=1]
#             [--xmlOutput=1]
#             [--singleValuedOption <value>]
#             [--singleValuedOption=<value>]
#             [--arrayValuedOption <value-1>,<value-2>,...]
#             [--arrayValuedOption=<value-1>,<value-2>,...]
#             [--hashValuedOption <key-1>=<value-1>,<key-2>=<value-2>,...]
#             [--hashValuedOption=<key-1>=<value-1>,<key-2>=<value-2>,...]
#             [<test> | <suite> | <test>::<case>]...
#
# @level{+}
#
# @item B<--baseTestClass> I<BASECLASS>
#
# Run tests derived from the given base class.  This argument is
# required and is usually set in the .options file.
#
# @item B<--suiteFile> I<FILE>
#
# Load in suites from the given suite file.  This argument is required
# if you want to run a suite and is usually set in the .options file.
#
# @item B<--config> I<FILE>
#
# Load Log4Perl configuration from the given file.  Defaults to
# I<log.conf>.
#
# @item B<--copySharedFiles> I<1>
#
# Use Permabit::FileCopier::copySrcFiles() to copy files
# into an NFS accessible location for use by remote machines.
#
# @item B<--exclude> I<test>[,<test>....]
#
# Exclude the given tests from those otherwise specified
#
# @item B<--excludeRegexp> I<REGEXP>
#
# Exclude all test suites matching the given REGEXP.
#
# @item B<--excludeSuites> I<suite>[,<suite>....]
#
# Exclude the tests from the given suites from those otherwise specified
#
# @item B<--expunge> I<option>[,<option>....]
#
# Expunge the "option" from the test, so that --option=value will replace
# the value instead of appending to it.
#
# @item B<--help> I<1>
#
# Print out help for runtests.pl.  If a testname is provided, print
# out options for both runtests.pl and for the given test.
#
# @item B<--JSON> I<1>
#
# Print out a JSON formatted tree for the specified suites and tests.
#
# @item B<--log> I<1>
#
# Redirect STDERR and STDOUT from each test that is run into a file
# named B<test>.stdout
#
# @item B<--logDir> I<DIR>
#
# Generate any log or xml files specified using I<--log=1> or
# I<--xmlOutput=1> in the specified directory.  Defaults to the current
# directory.
#
# @item B<--moveToMaintenance> I<1>
#
# If machines won't release, move them to maintenance
#
# @item B<--noRun> I<1>
#
# Don't run anything, just check the syntax of the specified tests.
#
# @item B<--promptOnErrorBeforeTearDown> I<1>
#
# If a test fails, prompt the user before calling the tear_down() method.
#
# @item B<--quiet> I<1>
#
# Don't print anything to STDOUT under normal execution.
#
# @item B<--repeat> [<COUNT>]
#
# Run the tests COUNT times, or until failure if COUNT is not specified.
#
# @item B<--sendChat>
#
# Send chat when tests finish.
#
# @item B<--symbols> I<1>
#
# Print out the alias table and the suite table, and do not run anything.
#
# @item B<--testRegexp> I<REGEXP>
#
# Only run test methods matching the given regexp.  For example,
# B<--testRegexp=foo> would run the methods I<testfoo> and I<testfoobar>
# inside a test, but not I<testbar>.  Defaults to matching all tests.
#
# @item B<--threads> I<COUNT>
#
# Run tests in COUNT separate threads for parallelization.  Defaults
# to 1 thread.  If thread count is greater than 1, logging is
# automatically enabled.
#
# @item B<--scale> [<RSVP-CLASS>]
#
# Dynamically adjust the number of threads depending on the available
# hosts in the specified class, default ALBIREO,FARM.
#
# @item B<--xmlOutput> I<1>
#
# Generate an XML file summarizing the results of each test that is run,
# in the same format output by Ant's JUnitXMLResultFormatter, to a file
# named B<test>.xml
#
# @item B<--singleValuedOption> I<value>
#
# Sets the value of the configuration option to the supplied value
#
# @item B<--arrayValuedOption> I<value-1>,I<value-2>,...
#
# Sets the value of the configuration option to an array ref containing the
# supplied values.
#
# @item B<--hashValuedOption> I<key-1>=I<value-1>,I<key-2>=I<value-2>,...
#
# Sets the value of the configuration option to a hash ref containing the
# supplied key-value pairs.
#
# @item I<suiteName|test|test::case ...>
#
# Run the given suite of tests, individual test or individual
# testcase.  By default all tests derived from the given baseTestClass
# are run.
#
# @level{-}
#
# @description
#
# The runtests.pl script is used to run one or more of the tests.
#
# Given no arguments, it will run all tests derived from the given
# baseTestClass.
#
# If an argument is the name of a suit from the testSuite file, that
# suite will be run.
#
# If the argument is a test name, it is assumed that the test name
# represents a file in the baseTestClass directory (or a subdirectory
# thereof), without the .pm extension (e.g. Add01).  Grandchildren of
# baseTestClass such as PerfTest/Pt1/Baseline.pm could be specified as
# Pt1::Baseline or PerfTest::Pt1::BaseLine.
#
# Otherwise the argument must be a test case name, specified as
# test_name::testcase.  A test such as testOtherDiesPhase2 of
# FailedJoinFast could be specified as
# FailedJoinFast::testOtherDiesPhase2 or
# CliqueTest::FailedJoinFast::testOtherDiesPhase2.
#
# $Id$
##
package Permabit::TestRunner;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use FindBin;

use File::Basename;
use File::Path;
use File::Spec;
use JSON;
use List::MoreUtils qw(uniq);
use List::Util qw(max);
use Log::Log4perl::Level;
use Log::Log4perl;
use POSIX qw(strftime :signal_h);
use Storable qw(dclone);
use Sys::CpuLoad;
use Sys::Hostname;
use Test::Unit::TestRunner;

use Pdoc::Generator qw(pdoc2help pdoc2usage);
use Permabit::Assertions qw(assertNumArgs);
use Permabit::Constants;
use Permabit::Exception qw(Signal);
use Permabit::FileCopier;
use Permabit::Options qw(parseARGV parseOptionsString);
use Permabit::Testcase;
use Permabit::RSVP;
use Permabit::Utils qw(
  findAllTests
  getSignalNumber
  getUserName
  makeFullPath
  mapConcurrent
  redirectOutput
  restoreOutput
  sendChat
);
use Permabit::XMLTestRunner;

# Log4perl Logging object
my $log = Log::Log4perl->get_logger(__PACKAGE__);

# This variable is set in the .options file
our $RUNTESTS_OPTIONS = {};

# These variables are set in the .suites file
our @addToDefaultTests;
our @excludes;
our %aliasNames;
our %aliasPrefixes;
our %suiteNames;

# These variables are read (never set) by Permabit::Testcase
our @expungements;
our %testOptions;

my @failures;
my @fullExcludes;
my @runtestsOptions;

my %killThreadsTime;
my %options;
my %threads;

my $baseTestClass;
my $caughtSigInt;
my $caughtSigUsr2;
my $config;
my $copySharedFiles;
my $currentSuite;
my $doLogging;
my $exclude;
my $excludeRegexp;
my $excludeSuites;
my $expunge;
my $help;
my $logDir;
my $nfsShareDir;
my $noRun; #TODO: streamline the whole no-run code path.
my $json;
my $jsonOutput;
my $numThreads = 1;
my $rsvper;
my $scale;
my $sharedNfsPrefix;
my $quiet;
my $repeat;
my $sendChat;
my $suiteFile;
my $symbols;
my $testRegexp;
my @tests;
my $xmlOutput;

my $MAX_LOAD    = 5;
my $MAX_THREADS = 10;

# SIGINT kills all current tests and exits
$SIG{INT} = sub {
  print(STDERR "Received a SIGINT, killing tests and suite.\n");
  $caughtSigInt = 1;
  killAllThreads('SIGUSR2');
};

# SIGHUP kills all current tests and then continues
$SIG{HUP} = sub {
  print(STDERR "Received a SIGHUP, killing tests only.\n");
  killAllThreads('SIGUSR2');
};

# SIGUSR2 kills the current test and suite.  Should never be sent by
# the user, only by the parent process signal handler.
$SIG{USR2} = sub {
  if (!$caughtSigUsr2) {
    print(STDERR "Received a SIGUSR2, stopping suite.\n");
    stopSuite();
    $caughtSigUsr2 = 1;
  }
  # if the current testcase is in tear_down(), just let it finish cleaning up
  if (!$Permabit::Testcase::inTeardown) {
    my $message = "Received a SIGUSR2, killing current test.";
    print(STDERR "$message\n");
    die(Permabit::Exception::Signal->new($message));
  }
};

######################################################################
##
sub main {
  assertNumArgs(0, @_);

  # Set a useful umask
  umask(02);

  # Parse command line options, get the test list, and run them
  loadOptions();
  parseArgs();
  if (!$doLogging) {
    # Make sure both STDOUT and STDERR are autoflushed so that
    # any progress dots gets printed immediately
    STDOUT->autoflush();
    STDERR->autoflush();
  }

  $sharedNfsPrefix //= lookUpSharedNfsPrefix();
  @tests = getTestList(@ARGV);
  if (!$noRun && $copySharedFiles) {
    copySharedFiles();
  }

  if ($json) {
    listTestsAsJSON();
  }

  for (my $i = 0; (($i < $repeat) || ($repeat == $FOREVER)); $i++) {
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime());
    if ($repeat != 1) {
      print("iteration " . ($i + 1) . "/"
            . (($repeat == $FOREVER) ? "FOREVER" : $repeat)
            . " -- $timestamp\n");
    }

    runTests(@tests);
    printSummary();
    if ($caughtSigInt) {
      delete $SIG{INT};
      kill($PID, getSignalNumber('INT'));
    }

    if (@failures) {
      last;
    }
  }

  if (!$noRun && $copySharedFiles) {
    removeSharedFiles();
  }

  if ($sendChat && (@failures == 0)) {
    sendChat(undef, $ENV{LOGNAME}, "runtests", "all tests passed");
  }

  return (scalar(@failures) > 0);
}

######################################################################
# See if there is a file of the name .$0[-.pl].options (ie, if $0 is
# runtests.pl, then look for .runtests.options), and if so, load the
# $RUNTESTS_OPTIONS hashref from it.
##
sub loadOptions {
  my $options = ".$FindBin::Script";
  $options =~ s/\.pl$/.options/;
  if (-f $options) {
    doFile($options);
  }
}

######################################################################
# Parse our command line options, and pass remaining options on to the
# tests.  Configure Log4Perl based on those options.
##
sub parseArgs {
  my $args = parseARGV();
  if (! ref($args)) {
    pdoc2usage($INC{"Permabit/TestRunner.pm"});
  }
  %options = %{$args};

  # Use $RUNTESTS_OPTIONS as defaults for %options
  foreach my $key (keys(%{$RUNTESTS_OPTIONS})) {
    if (!exists($options{$key})) {
      $options{$key} = $RUNTESTS_OPTIONS->{$key};
    }
  }

  # Extract options for us
  $baseTestClass   = getOption(\%options, 'baseTestClass',   undef);
  $config          = getOption(\%options, 'config',          'log.conf');
  $copySharedFiles = getOption(\%options, 'copySharedFiles', 0);
  $exclude         = getOption(\%options, 'exclude',         undef);
  $excludeRegexp   = getOption(\%options, 'excludeRegexp',   '');
  $excludeSuites   = getOption(\%options, 'excludeSuites',   undef);
  $expunge         = getOption(\%options, 'expunge',         undef);
  $help            = getOption(\%options, 'help',            0);
  $doLogging       = getOption(\%options, 'log',             0);
  $logDir          = getOption(\%options, 'logDir',          '.');
  $noRun           = getOption(\%options, 'noRun',           0);
  $json            = getOption(\%options, 'JSON',            0);
  $quiet           = getOption(\%options, 'quiet',           0);
  $repeat          = getOption(\%options, 'repeat',          -1);
  $sendChat        = getOption(\%options, 'sendChat',        0);
  $sharedNfsPrefix = getOption(\%options, 'sharedNfsPrefix', undef);
  $suiteFile       = getOption(\%options, 'suiteFile',       undef);
  $symbols         = getOption(\%options, 'symbols',         0);
  $testRegexp      = getOption(\%options, 'testRegexp',      '');
  $numThreads      = getOption(\%options, 'threads',         1);
  $scale           = getOption(\%options, 'scale',           0);
  $xmlOutput       = getOption(\%options, 'xmlOutput',       0);

  if (!$baseTestClass) {
    print("You must specify baseTestClass option\n");
    pdoc2usage($INC{"Permabit/TestRunner.pm"});
  }

  # help implies noRun
  if ($help) {
    $noRun = 1;
  }

  # noRun implies verifyReservations=0
  if ($noRun) {
    $options{verifyReservations} = 0;
  }

  if ($numThreads > 1 || $scale) {
    $doLogging = 1;
  }

  if ($repeat == 1) {
    # If the user specified --repeat, $repeat will be set to 1 by
    # Permabit::Options
    $repeat = $FOREVER;
  } elsif ($repeat == -1) {
    # If the user did not specify --repeat, $repeat will be set to -1
    $repeat = 1;
  } else {
    # The user specified --repeat N, nothing to do here
  }

  # Load in our test suites
  if ($suiteFile) {
    doFile($suiteFile);
  }

  # Add anything specified with --exclude to the @fullExcludes list
  if (ref($exclude) eq 'ARRAY') {
    push(@fullExcludes, @{$exclude});
  } elsif ($exclude) {
    push(@fullExcludes, $exclude);
  }

  # Add anything specified with --excludeSuites to the @fullExcludes list
  if ($excludeSuites) {
    my @suites;
    if (ref($excludeSuites) eq 'ARRAY') {
        @suites = @{$excludeSuites};
    } else {
        @suites = ($excludeSuites);
    }
    push(@fullExcludes, expandSuites(@suites));
  }

  # Add anything specified with --expunge to the @expungements list
  if (ref($expunge) eq 'ARRAY') {
    push(@expungements, @$expunge);
  } elsif ($expunge) {
    push(@expungements, $expunge);
  }

  # Print out the alias and suite tables
  if ($symbols) {
    printSymbols();
    exit(0);
  }

  # Initialize log4perl
  Log::Log4perl->init($config);
  # If we're not running, don't log anything
  if ($noRun) {
    Log::Log4perl::Logger->get_root_logger()->level($FATAL);
  }

  if ($help && !scalar(@ARGV)) {
    pdoc2help($INC{"Permabit/TestRunner.pm"});
  }
}

######################################################################
# "do" a file (with error checking)
#
# @param  name   name of the file
##
sub doFile {
  my ($name) = assertNumArgs(1, @_);
  if (!defined(do $name)) {
    if ($EVAL_ERROR) {
      die("Couldn't parse file \"$name\":  $EVAL_ERROR");
    } else {
      die("Couldn't read file \"$name\":  $OS_ERROR");
    }
  }
}

######################################################################
# Return the value of this parameter in the options hash if it is
# there, or return the default value.
##
sub getOption {
  my ($options, $name, $default) = assertNumArgs(3, @_);
  my $value = defined($options->{$name}) ? $options->{$name} : $default;
  delete($options->{$name});
  push(@runtestsOptions, $name);
  return $value;
}

######################################################################
# Get the list of tests that should be run
##
sub getTestList {
  my @args = @_;
  my @tests;

  if (scalar(@args) >= 1) {
    # tests were specified on the command-line
    @tests = @args;

    # If any suite names were listed, substitute the appropriate tests
    @tests = expandSuites(@tests);

    # If any alias names were listed, build and substitute appropriately
    expandAliases(\@tests);

    # normalize the test names by prepending ${baseTestClass}:: if needed
    @tests = map { normalizeTestName($_) } @tests;
  } else {
    # All modules are found and run by default (except those in the
    # @exclude list, which will be removed later).
    my @baseTests = findAllTests($baseTestClass);
    # Add additional aliased tests defined by the suite files.
    # Must process aliases as in the if-clause above.
    my @additionalTests = @addToDefaultTests;
    expandAliases(\@additionalTests);
    @additionalTests = map { normalizeTestName($_) } @additionalTests;
    # Always process the list in a defined order
    my %all = map { $_ => 1 } (@baseTests, @additionalTests);
    @tests = sort(keys(%all));
    push(@fullExcludes, @excludes);
  }

  return @tests;
}

######################################################################
# Do an initial --quiet --noRun pass of runTests() to fill in $jsonOutput with
# all the tests, then print $jsonOutput. This ensures triage can see all the
# tests that were supposed to be run even when the run is killed early.
##
sub listTestsAsJSON {
  assertNumArgs(0, @_);

  # Save the settings we're about to temporarily override.
  my @savedSettings = ($noRun, $quiet);

  # Quietly load all the tests, filling in $jsonOutput.
  $noRun = 1;
  $quiet = 1;
  $jsonOutput = {};
  runTests(@tests);

  # Restore the temporarily-overridden settings.
  ($noRun, $quiet) = @savedSettings;

  my $jsonFormatter = JSON->new->allow_nonref;
  $jsonFormatter    = $jsonFormatter->convert_blessed([1]);
  $jsonFormatter    = $jsonFormatter->allow_blessed([1]);
  $jsonFormatter    = $jsonFormatter->allow_unknown([1]);

  _print("JSON TEST STRUCTURE\n");
  _print($jsonFormatter->pretty->encode($jsonOutput));

  # Don't regenerate JSON during the actual test run.
  $json = 0;
  $jsonOutput = undef;
}

######################################################################
# Pick the shared NFS directory to use for files to be used by the
# test.
##
sub lookUpSharedNfsPrefix {
  assertNumArgs(0, @_);
  if ($ENV{SHARED_NFS_PREFIX}) {
    return $ENV{SHARED_NFS_PREFIX};
  }

  # We could look up the RSVP server being used, infer which of our
  # standard "not-backed-up" file systems is local to the test
  # machines, and use that via automounter. But that doesn't currently
  # work in our environment without some manual fixing. (See JIRA:
  # OPS-4210.)

  # Use locally-mounted directories and hope they're all the same.
  return "/permabit/not-backed-up";
}

######################################################################
# Copy server files to nfsShareDir.
##
sub copySharedFiles {
  assertNumArgs(0, @_);
  $nfsShareDir = ($sharedNfsPrefix . "/test/" . getUserName()
                  . "/CliqueTest/" . hostname() . "_$PID/");
  $options{nfsShareDir} = $nfsShareDir;

  system("rm -rf $nfsShareDir");
  mkpath($nfsShareDir);

  if (defined($main::SOURCE_FILES)) {
    my $savedOutput;
    if ($doLogging) {
      $savedOutput = redirectOutput("$logDir/filecopy.stdout");
    }
    Permabit::FileCopier->new(mainBase     => $main::DEFAULT_TOPDIR,
                              machine      => 'nfs',
                              targetBinDir => $nfsShareDir,
                              rsyncOptions => '--inplace',
                              sourceFiles  => $main::SOURCE_FILES,
                             )->copySrcFiles();
    if ($doLogging) {
      restoreOutput($savedOutput);
    }
  }
}

######################################################################
# Clean up nfsShareDir.
##
sub removeSharedFiles {
  if (defined($main::SOURCE_FILES)) {
    # With NFS lag, it may be faster to have multiple readdir/unlink
    # operations in the pipeline at once in parallel trees, if we know
    # of several subtrees we've created.
    my @subtrees = map {
      my $dest = $_->{dest};
      map {
        $nfsShareDir . "/" . $dest . "/" . basename($_);
      } @{$_->{files}};
    } @{$main::SOURCE_FILES};
    # Ignore errors in this pass. We may get plenty, if for example
    # "src/c++" and "src/c++/foo" are both among the destinations.
    # Also, rm seems to be a bit faster than rmtree.
    mapConcurrent {
      system("rm -rf $_");
    } @subtrees;
  }
  # Then make sure we clean up anything else, reporting any errors.
  rmtree($nfsShareDir);
}

######################################################################
# Extract any arguments that were specified in the suite file.  Merge
# these options with any specified on the command line, and pass all
# of them into the test via the Permabit::Testcase::setTestOptions
# mechanism.
#
# @return a list of (1) the test name and (2) the test arguments string.
##
sub setTestArguments {
  my ($test) = assertNumArgs(1, @_);

  # Begin with the command line options
  %testOptions = %{dclone(\%options)};

  # Separate out individual test options, if any.  These came from the suite
  # definition or the application of aliases.
  my ($testName, $testArgs) = ($test =~ /^(\S+)\s*(.*)$/);
  my ($optionsHash, @remaining) = parseOptionsString($testArgs);

  if ($doLogging) {
    $testOptions{logDir}  = File::Spec->rel2abs($logDir);
    $testOptions{rsvpMsg} = $testOptions{logDir} . '/' . $testName;
  } else {
    $testOptions{rsvpMsg} = $testName;
  }

  # Add the individual test options.
  while (my ($key, $value) = each %{$optionsHash}) {
    $testOptions{$key} = $value;
  }

  return ($testName, $testArgs);
}

######################################################################
# Print a line describing whether the test passed or failed, and how
# long it took.
#
# @param testName    The name of the test.
# @param retVal      The return value from the test
# @param startTime   The starting time of the test
##
sub printTestResult {
  my ($testName, $retVal, $startTime) = assertNumArgs(3, @_);
  my $diffTime = "(" . (time() - $startTime) . "s)";
  my $status = $retVal ? "ok" : "FAILURE";

  # testNames can be large (they're really the only way a test can quickly
  # express its purpose)
  printf("%-59s %8s %-10s\n", $testName, $status, $diffTime);
}

######################################################################
# Get the number of available hosts
#
# @param class  rsvp class to check
##
sub _availableHosts {
  my ($class) = assertNumArgs(1, @_);

  if (!$rsvper) {
    $rsvper = Permabit::RSVPer->new();
  }

  # Check for the case where the user specified no or an empty argument.
  if (!$class || ($class =~ /^1$/)) {
    $class = $rsvper->appendClasses(undef);
  }

  my $savedOutput;
  if ($doLogging) {
    $savedOutput = redirectOutput("$logDir/rsvp.log");
  }

  my $count = 0;
  foreach my $h (@{$rsvper->listHosts(class => $class)}) {
    if (!$h->[1]) {
      ++$count;
    }
  }
  if ($doLogging) {
    restoreOutput($savedOutput);
  }
  return $count;
}

######################################################################
# Should more threads be started.
##
sub _startMoreThreads {
  assertNumArgs(0, @_);
  my $currentThreads = scalar(keys(%threads));
  if ($currentThreads == 0) {
    return 1;
  }

  # Delay a little between launches of additional threads so
  # multiple children don't all hammer the RSVP server at once.
  # This also allows the previous test time to reserve its machines
  # before we check for available hosts again.
  sleep(1);

  if ($scale) {
    my $load = Sys::CpuLoad::load();
    if ($load > $MAX_LOAD) {
      $log->info("load $load is higher than $MAX_LOAD: throttling");
      return 0;
    }
    if ($currentThreads >= $MAX_THREADS) {
      $log->info("$currentThreads threads reached max ($MAX_THREADS):"
                . " throttling");
      return 0;
    }
    return _availableHosts($scale) > 0;
  }
  return $currentThreads < $numThreads;
}

######################################################################
# Run each of the specified tests.
#
# @param tests  The list of tests to run
##
sub runTests {
  my @tests = @_;

  # Generate map to easily check if tests should be excluded
  my %excludedTests;
  map { $excludedTests{normalizeTestName($_)} = 1; } @fullExcludes;

  # Run each of the specified tests
  foreach my $test (@tests) {
    if (!$noRun) {
      if (!_startMoreThreads()) {
        waitForThreadCompletion();
      }
      if ($caughtSigInt) {
        last;
      }
    }
    my ($testName, $testArgs) = setTestArguments($test);
    if ($excludedTests{$testName}) {
      next;
    }
    my @temp = split(/::/, $testName);
    if (($excludeRegexp ne '') && ($temp[1] =~ /$excludeRegexp/)) {
      next;
    }

    runTest($testName, $testArgs);
  }

  waitForAllThreads();
}

######################################################################
# Run the given test in a new thread and put that thread in %threads.
#
# @param test      The name of the test to run
# @param testArgs  The arguments that are passed to the test.
##
sub runTest {
  my ($test, $testArgs) = assertNumArgs(2, @_);
  my $thread = {};
  if (!$noRun) {
    _print("Starting $test\n");

    # Make sure logDir exists
    mkpath($logDir);

    if ($xmlOutput) {
      open($thread->{xmlOutput}, "> $logDir/$test.xml")
        or die("can't open $logDir/$test.xml: $OS_ERROR");
      $thread->{testRunner}
        = Permabit::XMLTestRunner->new($thread->{xmlOutput});
    } else {
      $thread->{testRunner} = Test::Unit::TestRunner->new();
    }

    # Set up filtering to only run the selected tests.  Let individual tests in
    # a suite have different test regexps.
    my $singleTestRegexp = getOption(\%testOptions, "testRegexp", "");
    if ($testRegexp) {
      $thread->{testRunner}->filter($testRegexp);
    } elsif ($singleTestRegexp) {
      $thread->{testRunner}->filter($singleTestRegexp);
      $singleTestRegexp = "";
    }
  }

  if ($doLogging) {
    my $path = "$logDir/$test.out";
    $thread->{outFile} = $path;
    my @logFiles = setLoggingForTest($test);
    $testOptions{logFiles} = [ $path, @logFiles ];
  }

  # Load the test
  $thread->{suite} = eval { loadTest($test); };
  my $load_EVAL_ERROR = $EVAL_ERROR;

  # If the test failed to load because the perl module doesn't exist,
  # the name may be in the form "test::case".  Try stripping off the
  # testcase name.
  my $CANT_LOCATE = "^Can't locate ";
  if ($load_EVAL_ERROR && ($load_EVAL_ERROR =~ m{$CANT_LOCATE})
      && ($test =~ m/^(.+)::(\w+)$/) && ($baseTestClass ne $1)) {
    my $testName = $1;
    my $caseName = $2;
    $thread->{suite} = eval { loadTest($testName); };
    if (!$EVAL_ERROR) {
      # Loading the test works, so adjust the filtering to only run
      # the named testcase.
      $noRun || $thread->{testRunner}->filter("\\b$caseName\$");
      $test = $testName;
      $load_EVAL_ERROR = undef;
    } elsif ($EVAL_ERROR !~ m{$CANT_LOCATE}) {
      # The test module exists, but it did not load.  Report the loading error.
      $test = $testName;
      $load_EVAL_ERROR = $EVAL_ERROR;
    }
  }
  # If loading failed, report the load failure.
  if ($load_EVAL_ERROR) {
    _err("Unable to load $test:\n\t$load_EVAL_ERROR");
    push(@failures, $test);
    printTestResult($test, 0, time());
    return;
  }
  # record the testname, now that we are sure we know it
  $thread->{test} = $test;

  my $lastTestName = "";
  if ($thread->{suite}->{_Tests}[-1]) {
    $lastTestName = $thread->{suite}->{_Tests}[-1]->{_fullName};
  }
  $thread->{suite}->{lastTestFullName} = $lastTestName;


  ######################################################################
  ######    GOOD SPOT FOR FIRST BREAKPOINT IF YOU'RE DEBUGGING    ######
  ######################################################################

  my @tests = @{$thread->{suite}->tests()};

  if ($help) {
    # Print options for the first test in the suite (all tests
    # should have more or less the same options)
    print("Usage: $0 [options] $test\n");
    print("\truntests options are:\n");
    print("\t\t" . join("\n\t\t", uniq(sort(@runtestsOptions))) . "\n");
    my $firstTest = $tests[0];
    if (defined($firstTest) && $firstTest->can("getCommandLineOptions")) {
      my @params = sort($firstTest->getCommandLineOptions());
      print("\t$test options are:\n");
      print("\t\t" . join("\n\t\t", @params) . "\n");
    }
    return;
  }

  if ($json) {
    my @testNames = map { $_->{_fullName} } @tests;
    $jsonOutput->{$test} = \@testNames;
  }

  if ($noRun) {
    _print("Checking $test (" . scalar(@tests) . " in suite)\n");
    my @isa = eval("return \@${test}::ISA");
    if (@isa) {
      _print("  base class : @isa\n");
    }
    if ($testArgs) {
      _print("  options    : $testArgs\n");
    }
    return;
  }

  $thread->{startTime} = time();
  my $s = sub {
    if ($thread->{outFile}) {
      redirectOutput($thread->{outFile});
      print STDERR "Running $test\n";
    }
    $currentSuite = $thread->{suite};
    if (!$thread->{testRunner}->do_run($thread->{suite}, 0)) {
      # Test failed, die so that AsyncSub counts this as a failure
      die('');
    }
  };

  $thread->{asyncSub} = Permabit::AsyncSub->new(code => $s);
  $thread->{asyncSub}->start();

  # Resolve the race between adding the thread to the threads table and a
  # SIGINT that stops all testing threads, by holding a block on SIGINT.
  my $adder = sub {
    # Put this thread object into the thread map
    $threads{$test} = $thread;
    # If we have already caught a SIGINT, we need to send the newly created
    # thread a SIGUSR2.
    if ($caughtSigInt) {
      $thread->{asyncSub}->kill("SIGUSR2");
    }
  };
  withBlockedSignal($adder, SIGINT);
}

######################################################################
# Run a block of code with a signal blocked.
#
# @param code    The code
# @param signal  The signal to block
#
# @croaks if the code dies or if the signal cannot be blocked.
##
sub withBlockedSignal {
  my ($code, $signal) = assertNumArgs(2, @_);
  my $oldSet = POSIX::SigSet->new();
  my $newSet = POSIX::SigSet->new($signal);
  sigprocmask(SIG_BLOCK, $newSet, $oldSet) or die("could not block signal");
  eval { $code->(); };
  my $blocked_EVAL_ERROR = $EVAL_ERROR;
  sigprocmask(SIG_SETMASK, $oldSet) or die("could not restore signal mask");
  if ($blocked_EVAL_ERROR) {
    die($blocked_EVAL_ERROR);
  }
}

######################################################################
# Load the test.
#
# @param test  The name of the test to load
#
# @return  a test suite object.  If there is an error, it will be
#          thrown using die.
##
sub loadTest {
  my ($test) = assertNumArgs(1, @_);
  return Test::Unit::Loader::load($test);
}

######################################################################
# Configure Log4perl to log to new files.  We want each test to log to separate
# logfiles based on the test name.  We need to do this dynamically since we may
# have multiple threads, each logging simultaneously.
#
# The A1 appender will be replaced to log to the path <testname>.log.  Any
# appender matching the pattern LOG[a-z]+ will be replaced to log to the
# path <testname>.<lower_case_suffix>.
#
# @param testName  The test name
#
# @return the list of log filenames.
##
sub setLoggingForTest {
  my ($testName) = assertNumArgs(1, @_);
  my @logFiles;

  # Replace the A1 appender.
  my $path = "$logDir/$testName.log";
  setLoggingToFile("A1", $path);
  push(@logFiles, $path);

  # Look for other appenders with a name starting with LOG, and replace those
  # appenders.
  foreach my $name (keys(%Log::Log4perl::Logger::APPENDER_BY_NAME)) {
    if ($name =~ m/^LOG(\p{IsLower}+)$/) {
      $path = "$logDir/$testName.$1";
      setLoggingToFile($name, $path);
      push(@logFiles, $path);
    }
  }
  return @logFiles;
}

######################################################################
# Replace a Log4perl appender with a new appender that logs to the given
# file.  Save the layout and threshold that were in log.conf so that user
# configuration still applies.
#
# @param name     The name of the appender
# @param logfile  The file to log to
##
sub setLoggingToFile {
  my ($name, $logfile) = assertNumArgs(2, @_);
  my $oldAppender = $Log::Log4perl::Logger::APPENDER_BY_NAME{$name};
  if (!$oldAppender) {
    die("No logger named $name in $config, can't enable logging\n");
  }
  # Save the old layout and threshold
  my $layout = $oldAppender->layout();
  my $threshold = $oldAppender->threshold();
  # Remove the old appender
  Log::Log4perl::Logger->eradicate_appender($name);
  # Create the new appender, using the old layout and threshold
  my $newAppender = Log::Log4perl::Appender->new("Log::Dispatch::File",
                                                 filename => $logfile,
                                                 mode     => "write",
                                                 name     => $name,
                                                );
  $newAppender->layout($layout);
  $newAppender->threshold($threshold);
  # Add the new appender
  Log::Log4perl::Logger->get_root_logger()->add_appender($newAppender);
}

######################################################################
# Wait for any of the currently running threads to complete.
#
# @return The name of the test that completed
##
sub waitForThreadCompletion {
  while (1) {
    foreach my $thread (values(%threads)) {
      if ($thread->{asyncSub}->isComplete()) {
        if ($xmlOutput) {
          close($thread->{xmlOutput})
            or die("can't close $logDir/$thread->{test}.xml: $OS_ERROR");
        }
        my $passed = ($thread->{asyncSub}->status() eq 'ok');
        printTestResult($thread->{test}, $passed, $thread->{startTime});
        if (!$passed) {
          push(@failures, $thread->{test});
        }
        delete($threads{$thread->{test}});
        return $thread->{test};
      }
    }
    # We are waiting for a thread to complete.  If we have caught a SIGINT,
    # send a SIGHUP to all our threads to request immediate cleanup.  We have
    # already done this once, but an eval might have trapped resulting
    # EVAL_ERROR, so we try again every 15 seconds.
    if ($caughtSigInt && (time() - $killThreadsTime{"SIGUSR2"} >= 15)) {
      killAllThreads('SIGUSR2');
    }
    # Sleep a little bit to avoid a busy loop.
    sleep(1);
  }
}

######################################################################
# Wait for all threads to complete
##
sub waitForAllThreads {
  while (scalar(keys(%threads))) {
    waitForThreadCompletion();
  }
}

######################################################################
# Send all threads the given signal.
#
# @param signal The signal to send to all threads
##
sub killAllThreads {
  my ($signal) = assertNumArgs(1, @_);
  $killThreadsTime{$signal} = time();
  foreach my $thread (values(%threads)) {
    $thread->{asyncSub}->kill($signal);
  }
}

######################################################################
# Stop any more tests in the currently running suite from running.
##
sub stopSuite {
  if ($currentSuite) {
    foreach my $testcase (@{$currentSuite->tests()}) {
      $testcase->stopSuite();
    }
  }
}

######################################################################
# Convert relative paths to files into package names for the file.
# Also prepend I<baseClass> to any testnames which lack it
##
sub normalizeTestName {
  my ($test) = assertNumArgs(1, @_);

  my @comp = split(/ /, $test);

  my $testName = $comp[0];

  #convert a path into a class name.
  $testName =~ s/\//::/g;
  $testName =~ s/\.pm$//;

  my $baseClass = $baseTestClass;
  $baseClass =~ s|/|::|g;

  if ($testName !~ /^${baseClass}::/) {
    $testName = "${baseClass}::$testName";
  }
  $comp[0] = $testName;
  return join(" ", @comp);
}

######################################################################
# Check to see if the names of any suites have been specified, and if
# so replace the suite names with the list of tests they specify.
##
sub expandSuites {
  my (@tests) = @_;
  return map { exists($suiteNames{$_}) ? @{$suiteNames{$_}} : ($_) } @tests;
}

######################################################################
# Check to see if the names of any aliases have been specified, and if
# so create the real test behind the alias.
##
sub expandAliases {
  my ($tests) = @_;
  my $prefixes = undef;
  if (scalar(keys(%aliasPrefixes)) > 0) {
    $prefixes = join("|", keys(%aliasPrefixes));
  }
  foreach my $testName (@$tests) {
    # find the name of the (potentially) aliased test
    if ($testName !~ m/^(\w+)/) {
      next;
    }
    my $aliasName   = $1;
    my $baseName    = undef;
    my $workingName = $1;
    if (defined($prefixes)) {
      while ($workingName =~ m/^($prefixes)(\w+)$/) {
        # The name has an aliasing prefix, so the rest of the name is the
        # "real" test, and add the command line options associated with the
        # prefix to the test command
        $baseName = "${baseTestClass}::$2";
        $testName .= " $aliasPrefixes{$1}";
        $workingName = $2;
      }
    }
    if (exists($aliasNames{$workingName})) {
      # The name is really an alias, so find the name of the "real" test,
      # and add the command line options from the alias to the test command
      my $aliasString = $aliasNames{$workingName};
      if ($aliasString =~ m/^(\w+::\w+)(.*)$/) {
        $baseName = $1;
        $testName .= $2;
      } else {
        $aliasString =~ m/^(\w+)(.*)$/;
        $baseName = "${baseTestClass}::$1";
        $testName .= $2;
      }
    }
    if (defined($baseName)) {
      # now create the "alias" test package at run time as a subclass of
      # the base test.  We do this so that the test result filenames
      # will use the alias name.
      no strict 'subs';
      eval "package ${baseTestClass}::$aliasName; use base $baseName;";
      if ($EVAL_ERROR) {
        die($EVAL_ERROR);
      }
    }
  }
}

######################################################################
# Print the alias and suite tables
##
sub printSymbols {
  if (%suiteNames) {
    print STDOUT "SUITES\n";
    foreach my $name (sort(keys(%suiteNames))) {
      print STDOUT "  $name\n";
    }
    print STDOUT "\n";
  }
  if (%aliasNames) {
    print STDOUT "ALIASES\n";
    foreach my $name (sort(keys(%aliasNames))) {
      print STDOUT "  $name\n";
    }
    print STDOUT "\n";
  }
  if (%aliasPrefixes) {
    my $n = max(map { length } keys(%aliasPrefixes));
    print STDOUT "ALIAS PREFIXES\n";
    foreach my $prefix (sort(keys(%aliasPrefixes))) {
      printf("  %-*s  %s\n", $n, $prefix, $aliasPrefixes{$prefix});
    }
    print STDOUT "\n";
  }
}

######################################################################
# Print a summary of the results of this test run.
##
sub printSummary {
  if (scalar(@tests) > 0) {
    if (scalar(@failures) > 0) {
      _err("The following " . scalar(@failures) . " tests failed:\n\t"
           . join(' ', @failures) . "\n");
    } else {
      _print("No tests failed.\n");
    }
    if ($caughtSigInt && (scalar(@tests) > 1)) {
      _err("Test run aborted due to SIGINT.\n");
    }
  }
}

######################################################################
# Return the log directory.  This may be used inside of log.conf to
# dynamically determine where to place logfiles.
#
# @return The directory in which logfiles should be placed
##
sub getLogDir {
  return $logDir || '.';
}

######################################################################
# Wrapper around print() to obey the quiet flag
##
sub _print {
  if (!$quiet) {
    print @_;
  }
}

######################################################################
# Wrapper around print(STDERR).
##
sub _err {
  print STDERR @_;
  if ($sendChat) {
    sendChat(undef, $ENV{LOGNAME}, "runtests", @_);
  }
}

######################################################################
# Wrapper around write() to obey the quiet flag
##
sub _write {
  if (!$quiet) {
    write();
  }
}

1;
