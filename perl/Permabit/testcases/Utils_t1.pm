##
# Test the Utils module
#
# $Id$
##
package testcases::Utils_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Data::Dumper;
use File::Temp qw(tmpnam);
use Permabit::Assertions qw(
  assertDefined
  assertEq
  assertEqualNumeric
  assertEvalErrorMatches
  assertFalse
  assertMinMaxArgs
  assertNENumeric
  assertNear
  assertNotDefined
  assertNumArgs
  assertRegexpMatches
  assertTrue
);
use Permabit::AsyncSub;
use Permabit::Constants;
use Permabit::Utils qw(
  arrayDifference
  arraySameMembers
  ceilMultiple
  getRandomGaussian
  getSignalNumber
  hashExtractor
  hashToArgs
  makeFullPath
  makeRandomToken
  mapConcurrent
  mergeToHash
  onSameNetwork
  openMaybeCompressed
  parseBytes
  parseISO8061toMillis
  reallySleep
  redirectOutput
  restoreOutput
  shortenHostName
  timeout
  timeToText
);
use POSIX qw(strftime);
use Statistics::Descriptive;
use Time::HiRes qw(time);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
##
sub tear_down {
  my ($self) = assertNumArgs(1, @_);
  map { unlink($_); } @{$self->{_localFiles}};
  $self->SUPER::tear_down();
}

######################################################################
##
sub testArrayDifference {
  my ($self) = assertNumArgs(1, @_);

  $self->assert(arraySameMembers([], arrayDifference([], [])));
  $self->assert(arraySameMembers([1], arrayDifference([1], [])));
  $self->assert(arraySameMembers([1, 2], arrayDifference([1, 2], [])));
  $self->assert(arraySameMembers([1], arrayDifference([1, 2], [2])));
  $self->assert(arraySameMembers([2], arrayDifference([1, 2], [1])));
}

######################################################################
##
sub testArraySameMembers {
  my ($self) = assertNumArgs(1, @_);
  # all of these should compare as equal
  my @aList = (
               ['a1', 1, 2, 'b2', 1],
               ['a1', 1, 2, 'b2', 2],
               ['a1', 'b2', 1, 2],
               [1, 2, 'b2', 1, 'a1'],
               ['a1', 1, 2, 'b2', 1, 1, 2, 1, 1, 1, 2, 'a1'],
              );
  # all of these should compare as not equal
  my @bList = (
               ['a1', 1, 2],
               ['a1', 'a1', 'a1', 'a1'],
               ['a1', 'b2', 1, 2, 3],
               ['a1', 'b2', 'c3', 1, 2],
               [],
              );
  # test for any list equals itself
  foreach my $r1 (@aList, @bList) {
    assertTrue(arraySameMembers($r1, $r1),
               $self->listCompareMessage($r1, '==', $r1));
  }
  # test for lists that should compare equal
  foreach my $r2a (@aList) {
    foreach my $r2b (@aList) {
      assertTrue(arraySameMembers($r2a, $r2b),
                 $self->listCompareMessage($r2a, '==', $r2b));
    }
  }
  # test for lists that should compare unequal
  foreach my $r3a (@aList) {
    foreach my $r3b (@bList) {
      assertTrue(!arraySameMembers($r3a, $r3b),
                 $self->listCompareMessage($r3a, '!=', $r3b));
      assertTrue(!arraySameMembers($r3b, $r3a),
                 $self->listCompareMessage($r3b, '!=', $r3a));
    }
  }
  foreach my $i4a (0 .. $#bList) {
    foreach my $i4b (0 .. $#bList) {
      if ($i4a != $i4b) {
        my $r4a = $bList[$i4a];
        my $r4b = $bList[$i4b];
        assertTrue(!arraySameMembers($r4a, $r4b),
                   $self->listCompareMessage($r4a, '!=', $r4b));
      }
    }
  }
}

######################################################################
# Make a list comparison message
##
sub listCompareMessage {
  my ($self, $a1, $c, $a2) = assertNumArgs(4, @_);
  return '(' . join(', ',@$a1) . ") $c (" . join(', ',@$a2) . ')';
}

######################################################################
##
sub testMergeToHash {
  my ($self) = assertNumArgs(1, @_);
  my $hashref = {};

  # Merge scalar
  mergeToHash($hashref, a => 1);
  $self->assert(scalar(keys %{$hashref}) == 1,
                "Wrong size of map: " . Dumper($hashref));
  assertEqualNumeric(1, $hashref->{a}, "hashref->{a} wrong");

  # Merge to non-existent list
  my %tmp;
  $tmp{b} = [1, 2];
  mergeToHash($hashref, %tmp);
  assertEqualNumeric(2, scalar(keys %{$hashref}),
                     "Wrong size of map: " . Dumper($hashref));
  assertEqualNumeric(2, scalar(@{$hashref->{b}}), "hashref->{b} wrong");
  assertEqualNumeric(1, $hashref->{b}->[0], "hashref->{b}->[0] wrong");
  assertEqualNumeric(2, $hashref->{b}->[1], "hashref->{b}->[1] wrong");
  # Make sure the original list was copied, not referenced
  $tmp{b}->[0] = 2;
  $self->assert($hashref->{b}->[0] == 1, "$hashref->{b}->[0] wrong");

  # Merge to non-existent hash
  my %tmp2;
  $tmp2{c} = {d => 3};
  mergeToHash($hashref, %tmp2);
  assertEqualNumeric(3, scalar(keys %{$hashref}),
                     "Wrong size of map: " . Dumper($hashref));
  assertEqualNumeric(1, scalar(keys %{$hashref->{c}}), "hashref->{c} wrong");
  assertEqualNumeric(3, $hashref->{c}->{d}, "hashref->{c}->{d} wrong");
  # Make sure the original hash was copied, not referenced
  $tmp2{c}->{d} = 2;
  assertEqualNumeric(3, $hashref->{c}->{d}, "hashref->{c}->{d} wrong");

  # Overwrite scalar
  mergeToHash($hashref, a => 2);
  assertEqualNumeric(3, scalar(keys %{$hashref}),
                     "Wrong size of map: " . Dumper($hashref));
  assertEqualNumeric(2, $hashref->{a}, "hashref->{a} wrong");

  # Merge list to existent scalar
  mergeToHash($hashref, a => [3, 4]);
  assertEqualNumeric(3, scalar(keys %{$hashref}),
                     "Wrong size of map: " . Dumper($hashref));
  assertEqualNumeric(3, scalar(@{$hashref->{a}}), "$hashref->{a} wrong");
  assertEqualNumeric(2, $hashref->{a}->[0], "hashref->{a}->[0] wrong");
  assertEqualNumeric(3, $hashref->{a}->[1], "hashref->{a}->[1] wrong");
  assertEqualNumeric(4, $hashref->{a}->[2], "hashref->{a}->[2] wrong");

  # Merge to existent list
  mergeToHash($hashref, b => [3]);
  assertEqualNumeric(3, scalar(keys %{$hashref}),
                     "Wrong size of map: " . Dumper($hashref));
  assertEqualNumeric(3, scalar(@{$hashref->{b}}), "hashref->{b} wrong");
  assertEqualNumeric(1, $hashref->{b}->[0], "hashref->{b}->[0] wrong");
  assertEqualNumeric(2, $hashref->{b}->[1], "hashref->{b}->[1] wrong");
  assertEqualNumeric(3, $hashref->{b}->[2], "hashref->{b}->[2] wrong");

  # Merge to existent hash
  mergeToHash($hashref, c => {e => 4});
  assertEqualNumeric(3, scalar(keys %{$hashref}),
                     "Wrong size of map: " . Dumper($hashref));
  assertEqualNumeric(2, scalar(keys %{$hashref->{c}}), "hashref->{c} wrong");
  assertEqualNumeric(3, $hashref->{c}->{d}, "hashref->{c}->{d} wrong");
  assertEqualNumeric(4, $hashref->{c}->{e}, "hashref->{c}->{e} wrong");
}

######################################################################
##
sub testHashExtractor {
  my ($self) = assertNumArgs(1, @_);

  # extract non-existant key
  my %hash;
  my %result = hashExtractor(\%hash, [1]);
  assertEqualNumeric(0, scalar(keys(%result)),
                     "Wrong size of map: " . Dumper(\%result));
  assertEqualNumeric(0, scalar(keys(%hash)),
                     "Added key to hash: " . Dumper(\%hash));

  # extract existant scalar
  $hash{1} = "a";
  %result = hashExtractor(\%hash, [1]);
  assertEqualNumeric(1, scalar(keys(%result)),
                     "Wrong size of map: " . Dumper(\%result));
  assertEq("a", $result{1}, "$result{1} wrong");

  # extract listref
  $hash{2} = [qw(b c)];
  %result = hashExtractor(\%hash, [1, 2]);
  assertEqualNumeric(2, scalar(keys(%result)),
                     "Wrong size of map: " . Dumper(\%result));
  assertEq("ARRAY", ref($result{2}));
  assertNENumeric($hash{2}, $result{2});
  $self->assert_deep_equals($hash{2}, $result{2});

  # extract hashref
  $hash{3} = { one => "d", two => "e" };
  %result = hashExtractor(\%hash, [2, 3]);
  assertEqualNumeric(2, scalar(keys(%result)),
                     "Wrong size of map: " . Dumper(\%result));
  assertEq("HASH", ref($result{3}));
  assertNENumeric($hash{3}, $result{3});
  $self->assert_deep_equals($hash{3}, $result{3});

  # extract only existant keys
  $hash{4} = undef;
  %result = hashExtractor(\%hash, [4, 5]);
  assertEqualNumeric(1, scalar(keys(%result)),
                     "Wrong size of map: " . Dumper(\%result));
  assertTrue(exists($result{4}));
  assertNotDefined($result{4});
  assertFalse(exists($result{5}));
}

######################################################################
##
sub testHashToArgs {
  my $self = shift;

  $self->assert(hashToArgs({ }) eq "");
  $self->assert(hashToArgs({ abc => "def" }) eq "--abc=def");
  $self->assert(hashToArgs({ abc => 1 }) eq "--abc=1");
  $self->assert(hashToArgs({ abc => undef }) eq "--abc");

  my $res = hashToArgs({ abc => 1, def => 2 });
  $self->_checkArgs($res, "--abc=1", "--def=2");

  $self->assert(hashToArgs({ abc => [ "one", "two", "three" ] })
                eq "--abc=one,two,three");

  $res = hashToArgs({ abc => "abc",
                      def => [ "a", "b", "c" ],
                      ghi => 4,
                      4 => 5
                    });
  $self->_checkArgs($res, "--abc=abc", "--def=a,b,c", "--ghi=4", "--4=5");

  $res = hashToArgs({ abc => { one => 1, two => 2, three => 3 }});
  my @args = split(' ', $res);
  $self->assert(scalar(@args) == 2);
  $self->assert($args[0] eq '--abc');
  my @subs = split(',', $args[1]);
  $self->assert(scalar(@subs) == 3);
  $self->assert(scalar(grep(/^one=1$/, @subs)) == 1);
  $self->assert(scalar(grep(/^two=2$/, @subs)) == 1);
  $self->assert(scalar(grep(/^three=3$/, @subs)) == 1);
}

sub _checkArgs {
  my ($self, $arg, @words) = @_;
  my @args = split(' ', $arg);
  $self->assert(scalar(@args) == scalar(@words));
  foreach my $w (@words) {
    $self->assert(scalar(grep(/^$w$/, @args)) == 1);
  }
}

######################################################################
##
sub testRedirectOutput {
  my ($self) = assertNumArgs(1, @_);
  my $file = tmpnam();
  push(@{$self->{_localFiles}}, $file);
  $log->debug("Redirecting output to $file");
  $self->assert(! -f $file, "$file exists");
  my $savedOutput = redirectOutput($file);
  print "STDOUT1\n";
  print STDOUT "STDOUT2\n";
  print STDERR "STDERR\n";
  restoreOutput($savedOutput);
  $self->assert(-f $file, "$file doesn't exist");
  open(FILE, "< $file") || die("couldn't open $file");
  my @lines = <FILE>;
  $self->assert($lines[0] eq "STDOUT1\n", "line 1 wrong: $lines[0]");
  $self->assert($lines[1] eq "STDOUT2\n", "line 2 wrong: $lines[1]");
  $self->assert($lines[2] eq "STDERR\n", "line 3 wrong: $lines[2]");
  $self->assert(@lines == 3, "wrong number of lines: @lines");
  close(FILE) || die("couldn't close $file");
}

######################################################################
#
##
sub testMakeRandomToken {
  my ($self) = assertNumArgs(1, @_);

  eval {
    makeRandomToken(0);
  };
  assertEvalErrorMatches(qr/positive length/);

  for my $i (1..30) {
    my $t = makeRandomToken(1);
    assertTrue($t > 0, "greater than zero");
    assertTrue($t < 10, "less than ten");
  }
}

######################################################################
##
sub testOpenMaybeCompressedNoFile {
  my ($self) = assertNumArgs(1, @_);

  my $r = openMaybeCompressed('/no/such/file');
  $self->assert(!$r);
}

######################################################################
##
sub testOpenMaybeCompressedPlain {
  my ($self) = assertNumArgs(1, @_);

  my $f = tmpnam();
  push(@{$self->{_localFiles}}, $f);
  open(F, ">$f") || die("cannot create $f: $ERRNO");
  print F "foo\n";
  close(F) || die("cannot close $f: $ERRNO");

  my $fh = openMaybeCompressed($f);
  my @lines = <$fh>;
  close($fh) || die("cannot close $f: $ERRNO");
  assertEqualNumeric(1, scalar(@lines));
  $self->assert_str_equals("foo\n", $lines[0]);
}

######################################################################
##
sub testOpenMaybeCompressedGz {
  my ($self) = assertNumArgs(1, @_);

  my $f = tmpnam() . ".gz";
  push(@{$self->{_localFiles}}, $f);
  open(F, "| gzip > $f") || die("cannot create $f: $ERRNO");
  print F "foo\n";
  close(F) || die("cannot close $f: $ERRNO");

  my $fh = openMaybeCompressed($f);
  my @lines = <$fh>;
  close($fh) || die("cannot close $f: $ERRNO");
  assertEqualNumeric(1, scalar(@lines));
  $self->assert_str_equals("foo\n", $lines[0]);
}

######################################################################
##
sub testOpenMaybeCompressedDevNull {
  my ($self) = assertNumArgs(1, @_);

  my $fh = openMaybeCompressed('/dev/null');
  my $l = <$fh>;
  $self->assert(!$l);
  close($fh) || die("cannot close /dev/null: $ERRNO");
}

######################################################################
##
sub testParseBytes {
  my ($self) = assertNumArgs(1, @_);
  my $testStr = "";

  # spaces
  $testStr = " $KB MB ";
  assertEqualNumeric($KB * $MB, parseBytes($testStr));

  # passthrough
  $testStr = $KB;
  assertEqualNumeric($KB, parseBytes($testStr));

  # mixed case
  $testStr = "${KB}Gb";
  assertEqualNumeric($KB * $GB, parseBytes($testStr));

  # single letter specifier
  $testStr = "${MB}b";
  assertEqualNumeric($MB, parseBytes($testStr));
}

######################################################################
##
sub testParseISO8061toMillis {
  my ($self) = assertNumArgs(1, @_);
  assertEqualNumeric(0,    parseISO8061toMillis(genISO8061(0, "000")));
  assertEqualNumeric(1,    parseISO8061toMillis(genISO8061(0, "001")));
  assertEqualNumeric(1000, parseISO8061toMillis(genISO8061(1, "000")));
  assertEqualNumeric(1001, parseISO8061toMillis(genISO8061(1, "001")));
}

######################################################################
##
sub genISO8061 {
  my ($sec, $millis) = @_;
  return strftime("%Y-%m-%d %H:%M:%S", localtime($sec)) . ",$millis";
}

######################################################################
##
sub testShortenHostname {
  my ($self) = assertNumArgs(1, @_);
  my @tests = (["foo-bar-quux.google.com", "foo-bar-quux.google.com"],
               ["10.123.123.1", "10.123.123.1"],
               ["www.google.com", "www.google.com"]);
  foreach my $test (@tests) {
    $self->assert_str_equals($test->[0], shortenHostName($test->[1]));
    $self->assert_str_equals($test->[0], shortenHostName("$test->[1]\n"));
    $self->assert_str_equals($test->[0], shortenHostName(" $test->[1] \n"));
  }
}

######################################################################
##
sub testMakeFullPath {
  my ($self) = assertNumArgs(1, @_);
  $self->assert_str_equals("/foo/bar/foo bar",
                           makeFullPath("/foo", "bar", "foo bar"));

  $self->assert_str_equals("./foo/bar", makeFullPath("foo/", "bar"));
  $self->assert_str_equals("./bar", makeFullPath("bar"));
  $self->assert_str_equals("./bar", makeFullPath(".", "bar"));
  $self->assert_str_equals("./bar", makeFullPath(".", "./bar"));
  $self->assert_str_equals("./bar", makeFullPath("./bar"));

  $self->assert_str_equals("./Foo/bar", makeFullPath('.', "./Foo", 'bar'));
  $self->assert_str_equals("./foo/bar", makeFullPath(".", ".", "foo", "bar"));
  $self->assert_str_equals("./bar/foo", makeFullPath("./bar", "foo"));

  my $p1 = makeFullPath("Foo", 'bar');
  my $p2 = makeFullPath("fred", 'barny');
  $self->assert_str_equals("./Foo/bar/fred/barny", makeFullPath($p1, $p2));
}

######################################################################
##
sub testTimeout {
  my ($self) = assertNumArgs(1, @_);
  my ($s, $e, $ee, @a);

  $e = eval { $s = timeout(60, sub { return 'foo'; }); };
  $ee = $EVAL_ERROR;
  assertDefined($e);
  $self->assert_str_equals($e, $s);
  $self->assert_str_equals('foo', $s);
  $self->assert_str_equals('', $ee);

  $e = eval { @a = timeout(60, sub { return ('foo', 'bar'); }); };
  $ee = $EVAL_ERROR;
  assertDefined($e);
  assertEqualNumeric(2, $e);
  assertEqualNumeric(2, scalar(@a));
  $self->assert_str_equals('foo', $a[0]);
  $self->assert_str_equals('bar', $a[1]);
  $self->assert_str_equals('', $ee);

  $e = eval { $s = timeout(1, sub { while (1) {} return 'foo'}); };
  $ee = $EVAL_ERROR;
  $self->assert(!defined($e));
  $self->assert_matches(qr/^Code took more than 1 second/, $ee);

  $e = eval { @a = timeout(1, sub { while (1) {} return ('foo', 'bar'); }); };
  $ee = $EVAL_ERROR;
  $self->assert(!defined($e));
  $self->assert_matches(qr/^Code took more than 1 second/, $ee);

  $e = eval { $s = timeout(1, sub { while (1) {} }, 'Bummer, dude'); };
  $ee = $EVAL_ERROR;
  $self->assert(!defined($e));
  $self->assert_matches(qr/^Bummer, dude/, $ee);
}

######################################################################
##
sub testReallySleep {
  my ($self) = assertNumArgs(1, @_);

  # Testing that reallySleep sleeps at least the requested number of seconds
  my @sleepTests = (0, 0.5, 1, 2.5, 5);
  foreach my $timeSleep (@sleepTests) {
    my $startTime = time();
    reallySleep($timeSleep);
    my $elapsed = time() - $startTime;
    $log->info("elapsed = $elapsed");
    $self->assert($timeSleep <= $elapsed,
                "reallySleep did not sleep at least $timeSleep "
                . "seconds (elapsed=$elapsed)");
  }
}

######################################################################
# Stress test for reallySleep()
##
sub testReallySleepWithSignals {
  my ($self) = assertNumArgs(1, @_);
  my $expected = 10;
  my $t;
  {
    local $SIG{ALRM} = sub { $log->debug("Caught SIGALRM") };
    $t = Permabit::AsyncSub->new(code =>
      sub {
        my $before = time();
        my $ret = reallySleep($expected);
        my $after = time();
        return { before => $before, after  => $after, returnCode => $ret };
      },
    );
    $t->start();
  }
  sleep(2);
  $t->kill('ALRM');
  $t->kill('ALRM');
  sleep(4);
  $t->kill('ALRM');
  $t->kill('ALRM');
  $t->kill('ALRM');
  $t->kill('ALRM');
  $t->kill('ALRM');
  sleep(1);
  $t->kill('ALRM');
  $t->kill('ALRM');
  $t->kill('ALRM');
  my $ret = $t->result();
  my $elapsed = $ret->{after} - $ret->{before};
  $log->info("elapsed = $elapsed");
  $self->assert($expected <= $elapsed,
                "reallySleep did not sleep at least $expected "
                . "seconds (elapsed=$elapsed)");
  $self->assert_equals(0, $ret->{returnCode},
                       "reallySleep returned a nonzero return code");
}

######################################################################
# Test that our concurrent version of the "map" operator works (in
# particular, with a code block, which requires correct processing of
# the prototype).
##
sub testMapConcurrent {
  my ($self) = assertNumArgs(1, @_);

  my @testInputs = (1, 2, 3, 9, 42, 63, 17);
  my @expectedValues = map { $_ * 7 } @testInputs;
  my @results = mapConcurrent { $_ * 7 } @testInputs;
  assertEq(join(",", @expectedValues), join(",", @results));

  @results = mapConcurrent(sub { $_ * 7 }, @testInputs);
  assertEq(join(",", @expectedValues), join(",", @results));

  # We should test raising exceptions and waiting for subprocess
  # completion, too.
}

######################################################################
# Check that getRandomGaussian generates the right distribution.
##
sub checkDistribution {
  my ($mean, $sigma) = assertMinMaxArgs(1, 2, @_);

  # If either of the above is undef, we verify that default parameters
  # do the right thing (giving the standard normal distribution with
  # mean 0 and sigma 1).
  my @fnArgs = ();
  if (!defined($mean)) {
    # use default mean and sigma by passing no args
    ($mean, $sigma) = (0, 1);
  } elsif (!defined($sigma)) {
    # use default sigma
    @fnArgs = ($mean);
    $sigma = 1;
  } else {
    @fnArgs = ($mean, $sigma);
  }

  # generate 1000 random values.
  my @values = map { getRandomGaussian(@fnArgs) } (1 .. 1000);
  my $stats = Statistics::Descriptive::Full->new();
  $stats->add_data(@values);
  # Mean should be within 0.1*sigma.
  assertNear($mean, $stats->mean(), 0.1 * $sigma, "mean for ($mean,$sigma)");
  # Sigma should be within 10% of its value
  assertNear($sigma, $stats->standard_deviation(), "10%",
             "sigma for ($mean,sigma)");
}

######################################################################
# Test getRandomGaussian().
##
sub testGetRandomGaussian {
  my ($self) = assertNumArgs(1, @_);
  # Test various pairs of mean and standard deviations.
  my @means = (undef, 0, 0.5, -0.5, 1, -1, -50, 50);
  my @sigmas = (undef, 0.1, 1, 10, 100);
  for my $mean (@means) {
    for my $sigma (@sigmas) {
      # this will fail randomly, so try a second time if we get unlucky.
      # Of course, occasionally it will fail randomly TWICE. Oh well...
      eval {
        checkDistribution($mean, $sigma);
      };
      if ($EVAL_ERROR) {
        $log->warn("Failed first time. Trying again...");
        checkDistribution($mean, $sigma);
      }
    }
  }
}

######################################################################
# Test getSignalNumber().
##
sub testGetSignalNumber {
  my ($self) = assertNumArgs(1, @_);
  assertEqualNumeric(0, getSignalNumber('ZERO'));
  assertEqualNumeric(9, getSignalNumber('KILL'));
  eval {
    getSignalNumber('FOOBAR');
  };
  assertRegexpMatches(qr/Unknown signal name: FOOBAR/s, $EVAL_ERROR);
}

######################################################################
# Test timeToText().
#
# Check a variety of magnitudes, check for round-off and retaining
# leading zeros in formats, and check for correct labels.
##
sub testTimeToText {
  my ($self) = assertNumArgs(1, @_);
  my %expectedResults
    = (
       7 * $DAY             => "168:00:00",
       25 * $HOUR           => "25:00:00",
       3678                 => "1:01:18",
       3678.1001            => "1:01:18.100",
       3678.9001            => "1:01:18.900",
       3668.0101            => "1:01:08.010",
       367                  => "6:07",
       367.1                => "6:07.100",
       367.1001             => "6:07.100",
       367.1009             => "6:07.101",
       36.1001              => "36.100 seconds",
       36.1009              => "36.101 seconds",
       3.1001               => "3.100 seconds",
       300.1 * $MILLISECOND => "0.300 seconds",
       30.1 * $MILLISECOND  => "0.030 seconds",
       3.1 * $MILLISECOND   => "3.100 milliseconds",
       310 * $MICROSECOND   => "0.310 milliseconds",
       31 * $MICROSECOND    => "0.031 milliseconds",
       3100 * $NANOSECOND   => "3.100 microseconds",
       310 * $NANOSECOND    => "0.310 microseconds",
       31 * $NANOSECOND     => "0.031 microseconds",
       3.1 * $NANOSECOND    => "0.003 microseconds",
       0.31 * $NANOSECOND   => "0.000 microseconds", # Not ideal, but....
       0                    => "0 seconds",
      );
  foreach my $seconds (keys(%expectedResults)) {
    my $expected = $expectedResults{$seconds};
    my $actual = timeToText($seconds);
    assertEq($expected, $actual);
  }
}

######################################################################
# Test onSameNetwork().
##
sub testOnSameNetwork {
  my ($self) = assertNumArgs(1, @_);
  my $address1 = '1.35.69.103';
  my $encoded = unpack('I', pack('C4', split('\.', $address1)));
  for (my $sameUntil = 0; $sameUntil <= 32; $sameUntil++) {
    my $mask = (2 ** $sameUntil) - 1;
    my $encoded2 = ($encoded & $mask) | ((~$encoded) & (~$mask));
    my $address2 = join('.', unpack('C4', pack('I', $encoded2)));
    for (my $networkBits = 0; $networkBits <= 32; $networkBits++) {
      assertEq(onSameNetwork($address1, $address2, $networkBits),
               ($sameUntil >= $networkBits));
    }
  }
}

######################################################################
# Test ceilMultiple with one set of inputs.
#
# @param value     The value to ceiling
# @param multiple  The multiple (a positive integer) to ceiling to
# @param expected  The expected rounded-up value
##
sub _doCeilingTest {
  my ($value, $multiple, $expected) = assertNumArgs(3, @_);
  assertEqualNumeric($expected, ceilMultiple($value, $multiple));
  # Undocumented: Should passing a string containing a number work,
  # and get an implicit conversion to number? If so, it shouldn't get
  # a wacky result -- e.g., any Perl magic to figure out whether an
  # argument is an int or a float, if it assumes strings are never
  # passed, might go down the wrong path with a string. So verify that
  # *either* strings produce errors or they get the same numeric
  # result.
  my $result = undef;
  eval {
    $result = ceilMultiple("$value", $multiple);
  };
  if (defined($result)) {
    assertEqualNumeric($expected, $result);
  } else {
    $log->info("ceilMultiple(\"$value\",$multiple) rejected string form");
  }
}

######################################################################
# Test ceilMultiple with a variety of values.
##
sub testCeilMultiple {
  my ($self) = assertNumArgs(1, @_);
  _doCeilingTest(1.4, 1, 2);
  # ceil rounds towards positive infinity
  _doCeilingTest(-1.4, 1, -1);

  _doCeilingTest(59, 16, 64);

  _doCeilingTest(-2.1,        2, -2);
  _doCeilingTest(-2,          2, -2);
  _doCeilingTest(-2.0,        2, -2);
  _doCeilingTest(-1.9,        2,  0);
  _doCeilingTest(-1,          2,  0);
  _doCeilingTest( 0,          2,  0);
  _doCeilingTest( 1,          2,  2);
  _doCeilingTest( 1.0,        2,  2);
  _doCeilingTest( 1.99999999, 2,  2);
  _doCeilingTest( 2,          2,  2);
  _doCeilingTest( 2.0,        2,  2);
  _doCeilingTest( 2.00000001, 2,  4);
  _doCeilingTest( 3,          2,  4);
  _doCeilingTest( 4,          2,  4);
  _doCeilingTest( 4.0,        2,  4);

  # 2**62, except "2**62" would be done as floating point.
  #
  # Make sure we get reasonably high precision for integer values. If
  # calculations are done as IEEE double-precision floating point, we
  # get quite a bit less than 62 bits to work with.
  _doCeilingTest(4611686018427387904, 100, 4611686018427388000);
  _doCeilingTest(4611686018427387904,   3, 4611686018427387906);
  _doCeilingTest(4611686018427387904,   7, 4611686018427387907);
}

1;
