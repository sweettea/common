##
# Test the Permabit::SystemUtils module
#
# $Id$
##
package testcases::SystemUtils_t1;

use strict;
use warnings FATAL => qw(all);
use autodie qw(mkdir);

use Carp qw(croak);
use English qw(-no_match_vars);
use IO::File;
use Permabit::Assertions qw(
  assertEq
  assertEqualNumeric
  assertEvalErrorMatches
  assertMinArgs
  assertNumArgs
  assertRegexpMatches
);
use Permabit::Constants;
use Permabit::SystemUtils qw(
  assertCommand
  assertSystem
  createRemoteFile
  getNfsTempFile
  relink
  runCommand
  runPkill
  runSystemCommand
  slurp
  waitForMachines
  waitForResult
);
use Permabit::Utils qw(getUserName makeRandomToken);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
##
sub tear_down {
  my ($self) = assertNumArgs(1, @_);
  map { unlink($_) } @{$self->{_tempfiles}};
  $self->SUPER::tear_down();
}

######################################################################
##
sub testPkill {
  my ($self) = assertNumArgs(1, @_);

  # Attempt to kill a fake process.  The status code returned by this
  # should be 1.
  my $host = "localhost";
  assertEqualNumeric(1, runPkill($host, "thisIsAFakeProcess")->{status});

  # Make sure there are no "sleep" processes active (so to speak)
  assertEqualNumeric(1, runCommand($host, "pgrep sleep")->{status});
  # Start a long sleep.  We plan to kill it.
  assertCommand($host, "sleep 3600 &");
  # Wait for it to really be running
  while (runCommand($host, "pgrep sleep")->{status} == 1) {
  }
  # Make sure sleep is killed
  assertEqualNumeric(0, runPkill($host, "sleep")->{status});
  # Make sure there are no "sleep" processes active (so to speak)
  assertEqualNumeric(1, runCommand($host, "pgrep sleep")->{status});
}

######################################################################
##
sub testCreateRemoteFile {
  my ($self) = assertNumArgs(1, @_);
  my $host = $self->reserveHost();
  $self->fileTest($host, "/tmp/" . getUserName() . "-" . makeRandomToken(16));
  $self->fileTest($host, "/etc/" . getUserName() . "-" . makeRandomToken(16));

  my $newFile = createRemoteFile($host, "foo");
  my $result  = assertCommand($host, "cat $newFile");
  assertRegexpMatches(qr/foo/, $result->{stdout});
}

######################################################################
##
sub reserveHost {
  my ($self) = assertNumArgs(1, @_);
  local $self->{hostClass} = "FARM";
  local $self->{hostLabel} = "host";
  local $self->{hostNames} = undef;
  local $self->{numHosts}  = 1;
  $self->reserveHostGroup("host");
  return $self->{hostNames}[0];
}

######################################################################
##
sub fileTest {
  my ($self, $host, $filename) = assertNumArgs(3, @_);
  assertCommand($host, "test ! -f $filename");
  my $contents = <<HERE;
line1
line2
HERE
  createRemoteFile($host, $contents, $filename);
  my $result = assertCommand($host, "cat $filename");
  assertRegexpMatches(qr/line1/, $result->{stdout});
  assertRegexpMatches(qr/line2/, $result->{stdout});
  assertCommand($host, "sudo rm -f $filename");
}

######################################################################
##
sub testWaitForMachines {
  my ($self) = assertNumArgs(1, @_);
  eval {
    waitForMachines(1,1,1,1,"iwillnotresolve");
    $self->fail("should have failed");
  };
  waitForMachines(1,1,1,1,"localhost");
}

######################################################################
##
sub testWaitForResult {
  my ($self) = assertNumArgs(1, @_);
  foreach my $host ('127.0.0.1', 'localhost') {
    eval {
      waitForResult($host, "/bin/false",
                    sub { my $res = shift; return $res->{returnValue} == 0; },
                    10, "should never happen");
      $self->fail("should have failed");
    };
    my $file = "/tmp/waitForRemoteResult$$";
    system("rm -f $file");
    eval {
      waitForResult($host, "if test -f $file; then exit 0; else touch $file && exit 1; fi;",
                    sub { my $res = shift; return $res->{returnValue} == 0; },
                    10, "should never happen");
    };
    if ($EVAL_ERROR) {
      $self->fail("eval failed: $EVAL_ERROR");
    }
    system("rm -f $file");
  }
}

######################################################################
##
sub testRelinkBasic {
  my ($self) = assertNumArgs(1, @_);
  my $dir = relinkSetup();
  relink("$dir/sut1-link", "$dir/sut1-dir1");
}

######################################################################
# Test that relink() will still work if we aren't the owner.
##
sub testRelinkChown {
  my ($self) = assertNumArgs(1, @_);
  my $dir = relinkSetup();
  assertSystem("sudo chown root $dir/sut1-link");
  relink("$dir/sut1-link", "$dir/sut1-dir1");
}

######################################################################
##
sub relinkSetup {
  assertNumArgs(0, @_);
  my $dir = File::Temp->newdir('relinkSetup-XXXX', CLEANUP => 1, DIR => '/u1');
  assertSystem("mkdir $dir/sut1-dir0");
  assertSystem("mkdir $dir/sut1-dir1");
  assertSystem("ln -s $dir/sut1-dir0 $dir/sut1-link");
  return $dir;
}

######################################################################
# Run a single testcase from testRunCommand() with the command both as a string
# and as an arrayref
#
# @param host  The host on which to run the command
# @param case  The test case to run
##
sub runCommandTest {
  my ($host, $case) = assertNumArgs(2, @_);
  my $cmd = $case->{cmd};
  foreach my $mode (qw(string arrayref)) {
    $log->debug("Testing with $cmd as $mode");
    my $result = runCommand($host,
                            (($mode eq 'string') ? $cmd : [split(' ', $cmd)]));
    $log->debug("runCommand cmd: $result->{commandString}");
    assertEq($case->{out}, $result->{stdout},
             "stdout from running '$cmd' on $host");
    assertRegexpMatches($case->{err}, $result->{stderr},
                        "stderr from running '$cmd' on $host");
    assertEqualNumeric($case->{ret}, $result->{status},
                       "return code did not match");
  }
}

######################################################################
##
sub testRunCommand {
  my ($self) = assertNumArgs(1, @_);
  my $result;
  my @cases = ({
                cmd => q{echo foo},
                out => "foo\n",
                err => qr/^$/,
                ret => 0,
               },
               {
                cmd => q{'echo foo'},
                out => "",
                err => qr/not found/,
                ret => 127,
               },
               {
                cmd => q{"echo foo"},
                out => "",
                err => qr/not found/,
                ret => 127,
               },
               {
                cmd => q{export X=4; echo $X && echo $X},
                out => "4\n4\n",
                err => qr/^$/,
                ret => 0,
               },
               {
                cmd => q{'export X=4; echo $X && echo $X'},
                out => "",
                err => qr/not found/,
                ret => 127,
               },
               {
                cmd => q{"export X=4; echo \$X && echo \$X"},
                out => "",
                err => qr/not found/,
                ret => 127,
               },
               {
                cmd => q{export X=4; echo \$X && echo \$X},
                out => q{$X}."\n".q{$X}."\n",
                err => qr/^$/,
                ret => 0,
               },
               {
                cmd => q{export X=4; echo '\$X' && echo '\$X'},
                out => q{\$X}."\n".q{\$X}."\n",
                err => qr/^$/,
                ret => 0,
               },
               {
                cmd => q{echo -n '\'},
                out => q{\\},
                err => qr/^$/,
                ret => 0,
               },
               {
                cmd => q{echo -n \\\\},
                out => q{\\},
                err => qr/^$/,
                ret => 0,
               },
               {
                cmd => q{exit 42},
                out => "",
                err => qr/^$/,
                ret => 42,
               },
              );

  # runCommand() has a different code path if host is 'localhost'.
  foreach my $host ('localhost', '127.0.0.1') {
    foreach my $case (@cases) {
      runCommandTest($host, $case);
    }
  }
}

######################################################################
# Test runCommand() with a nonexistent host
##
sub testRunCommandNowhere {
  my ($self) = assertNumArgs(1, @_);

  my $result = runCommand('this-host-should-not-exist.example.com',
                          'echo hi');

  assertEqualNumeric(255, $result->{status},
                     'ssh to nowhere did not return 255');
}


######################################################################
##
sub testRunCommandTruncatedOutput {
  my ($self) = assertNumArgs(1, @_);
  my $line = ("a" x 49) . "\n";
  # the output limit must be at least as long as the ssd debug output
  # from remote commands.
  my $n = 100;
  my $verboseCommand = qq(perl -e 'print "$line" x $n');

  # Check that this commands run ok normally
  local $Permabit::SystemUtils::MAX_CMD_OUTPUT = (length($line) * $n);
  assertSystem($verboseCommand);
  assertSystem($verboseCommand);

  # Make the max output just a little bit too small.
  --$Permabit::SystemUtils::MAX_CMD_OUTPUT;
  eval { assertSystem($verboseCommand) };
  assertEvalErrorMatches(qr/too much output produced/, "local command");
}

######################################################################
# Test slurp
##
sub testSlurp {
  my ($self) = assertNumArgs(1, @_);

  my $fileContents = <<'_EOF';
this is
a file with
some contents.
Yup.
_EOF
  chomp($fileContents);
  my $tmpFile = "/tmp/SystemUtils_t1_testSlurp.$$";
  push(@{$self->{_tempfiles}}, $tmpFile);
  open(my $fh, "> $tmpFile") or die("unable to open $tmpFile");
  print $fh $fileContents;
  close($fh) or die("unable to close $tmpFile");

  my @lines = slurp($tmpFile);
  assertEq($fileContents, join("\n", @lines), "file contents differ");

  my $changedContents;
  ($changedContents = $fileContents) =~ s/i/X/g;
  assertEq($changedContents, join("\n", slurp("sed 's/i/X/g' $tmpFile |")),
           "stream contents differ");
}

######################################################################
# Return the current tail file descriptor.
##
sub _getCurrentFD {
  assertNumArgs(0, @_);

  my $fh = new IO::File "< /dev/null";
  my $fd = $fh->fileno();
  $fh->close();
  return $fd;
}

######################################################################
# Verify no fd were leaked.
#
# @param sub    function to run
##
sub _assertNoFdUsed {
  my ($self, $sub) = assertNumArgs(2, @_);

  my $fd0 = _getCurrentFD();
  $sub->();
  my $fd1 = _getCurrentFD();
  $log->debug("old $fd0, new $fd1");
  assertEqualNumeric($fd0, $fd1, "fd returned by open has changed");
}

######################################################################
# Verify that _doSystem() does not leak file descriptors.
##
sub testDoSystemFDClose {
  my ($self) = assertNumArgs(1, @_);

  $self->_assertNoFdUsed(sub {
                           runSystemCommand("true");
                         });
}

######################################################################
# Verify that the doSystem timeout mechanism works
##
sub testDoSystemTimeout {
  my ($self) = assertNumArgs(1, @_);
  assertSystem("true");
  {
    local $Permabit::SystemUtils::doSystemTimeout = $MINUTE;
    assertSystem("true");
  }
  {
    local $Permabit::SystemUtils::doSystemTimeout = 1;
    # expect to timeout, returning status 124
    my $result = runSystemCommand("sleep 60");
    assertEqualNumeric(124 * 256, $result->{returnValue});
  }
}

######################################################################
# Verify that getNfsTempFile does not leak file descriptors.
##
sub testGetNfsTempFileFDClose {
  my ($self) = assertNumArgs(1, @_);

  $self->_assertNoFdUsed(sub {
                           getNfsTempFile();
                         });
}

######################################################################
# Verify that runCommand does not leak file descriptors.
##
sub testRunCommandFDClose {
  my ($self) = assertNumArgs(1, @_);
  my $host = $self->reserveHost();

  # Sometimes a unix domain socket for sssd is opened while runCommand() is
  # running, causing the test to fail. Doing an unchecked invocation first is
  # an attempt to trigger that when it won't break the test.
  runCommand($host, 'true');

  $self->_assertNoFdUsed(sub {
                           runCommand($host, 'true');
                         });
}

1;
