##
# Test the Permabit::RSVP module
#
# $Id$
##
package testcases::RSVP_t1;

use strict;
use warnings FATAL => qw(all);
use Carp qw(croak);
use English qw(-no_match_vars);
use Log::Log4perl;

use File::Temp qw(tempfile);
use Permabit::Assertions qw(
  assertDefined
  assertEq
  assertEqualNumeric
  assertEvalErrorMatches
  assertMinArgs
  assertNumArgs
  assertRegexpMatches
);
use Permabit::AsyncSub;
use Permabit::ConfiguredFactory;
use Permabit::Constants;
use Permabit::RSVP;
use Permabit::Utils qw(getUserName);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my $rsvp;
my $params = {};

# used to hold checkServer results, indexed by host
my $checkServer;
my $numCheckServerCalls;

# used to hold ps results, indexed by host
my $ps;
my $numPsCalls;

# the params passed to _request
my $requestParams;

# hosts to return for _getHostsToRelease(all)
my @hostsToRelease;

# Reponses to be returned by _request
my @responses;

######################################################################
##
sub set_up {
  my ($self) = @_;
  $log->info("STARTING new testcase: " . $self->name());
  $rsvp = new Permabit::RSVP(dhost => "bogus",
                             user  => "bob",
                             releaseRetryTimeout => 0,
                             reserveRetryTimeout => 0,
                             retryMultiplier => 1);

  # Override RSVP _request and runAthinfo to facilitate testing. Keep track
  # of the original methods so that they can be restored in tear_down.
  {
    no warnings;
    $self->{_request}                   = \&Permabit::RSVP::_request;
    $self->{runAthinfo}                 = \&Permabit::RSVP::runAthinfo;
    $self->{_getHostsToRelease}         = \&Permabit::RSVP::_getHostsToRelease;
    *Permabit::RSVP::_request           = \&_rsvpRequest;
    *Permabit::RSVP::runAthinfo         = \&_rsvpRunAthInfo;
    *Permabit::RSVP::_getHostsToRelease = \&_rsvpGetHostsToRelease;
  }

  $numCheckServerCalls = 0;
  $numPsCalls = 0;
  $requestParams = {};
  $checkServer = {};
  $ps = {};
  @hostsToRelease = ();

  @responses = ({ type => "success", message => "happy"});

  $params = { host => "host-1000",
              msg  => "a message"
            };
}

######################################################################
# Restore the RSVP methods so that other tests aren't effected
##
sub tear_down {
  my ($self) = @_;
  {
    no warnings;
    *Permabit::RSVP::_request           = $self->{_request};
    *Permabit::RSVP::runAthinfo         = $self->{runAthinfo};
    *Permabit::RSVP::_getHostsToRelease = $self->{_getHostsToRelease};
  }
  if (defined($self->{testConfigFile})) {
    eval { unlink($self->{testConfigFile}); }
  }
}

######################################################################
##
sub testReleaseHost {
  my ($self) = @_;

  $rsvp->releaseHost(%{$params});
  $self->assert($numCheckServerCalls == 1,
                "Wrong number calls to checkServer: $numCheckServerCalls");
  $self->assert($numPsCalls == 1,
                "Wrong number calls to athinfo ps: $numPsCalls");
  $self->assertHost($params);
}

######################################################################
##
sub testReleaseHostCheckServerRetry {
  my ($self) = @_;

  $checkServer->{"host-1000"} = ["FAILURE"];
  $rsvp->releaseHost(%{$params});
  $self->assert($numCheckServerCalls == 2,
                "Wrong number calls to checkServer: $numCheckServerCalls");
  $self->assert($numPsCalls == 1,
                "Wrong number calls to athinfo ps: $numPsCalls");
  $self->assertHost($params);
}

######################################################################
##
sub testReleaseHostPsRetryExceeded {
  my ($self) = @_;

  # We have more failures then the number of retry attempts allowed
  $checkServer->{"host-1000"} = [];
  $ps->{"host-1000"} = ["bob ", "/blah/blah/pbnfsd ", "/var/tmp/pbnfsmon ",
                        "/foo/bar/java ", "/some/heartbeat ", "the/apphbd "];

  eval {
    $rsvp->releaseHost(%{$params});
  };
  $self->assert($EVAL_ERROR, "releaseHost didn't croak: $EVAL_ERROR");
  $self->assert($numCheckServerCalls == $rsvp->{releaseRetryCount},
                "Wrong number calls to checkServer: $numCheckServerCalls");
  $self->assert($numPsCalls == $rsvp->{releaseRetryCount},
                "Wrong number calls to athinfo ps: $numPsCalls");
}

######################################################################
##
sub testReleaseHostPsRetry {
  my ($self) = @_;

  $checkServer->{"host-1000"} = [];
  $ps->{"host-1000"} = ["FAILURE", "/some/heartbeat ", "the/apphbd "];

  $rsvp->releaseHost(%{$params});
  $self->assert($numCheckServerCalls == 4,
                "Wrong number calls to checkServer: $numCheckServerCalls");
  $self->assert($numPsCalls == 4,
                "Wrong number calls to athinfo ps: $numPsCalls");
  $self->assertHost($params);
}

######################################################################
##
sub testReleaseHostAll {
  my ($self) = @_;

  $params = { all => 1,
              msg  => "a message"
            };
  @hostsToRelease = ("host-1000", "host-1001");
  $ps->{"host-1001"} = ["/foo/bar/java "];

  $rsvp->releaseHost(%{$params});
  $self->assert($numCheckServerCalls == 3,
                "Wrong number calls to checkServer: $numCheckServerCalls");
  $self->assert($numPsCalls == 3,
                "Wrong number calls to athinfo ps: $numPsCalls");
  $params->{host} = "host-1001";
  $self->assertHost($params);
}

######################################################################
##
sub testReserveHostsByClassWithoutRetry {
  my ($self) = @_;

  $params = { wait => 0,
              class => "FARM",
              numhosts => 1
            };
  @responses = ({ type => "success",
                  data => ["host-1001"],
                });

  my @result = $rsvp->reserveHosts(%{$params});
  $self->assert($result[0] eq "host-1001",
                "Wrong machine reserved: $result[0]");

  $params = { wait => 0,
              class => ["FARM"],
              numhosts => 1
            };
  @responses = ({ type => "success",
                  data => ["host-1001"],
                });

  @result = $rsvp->reserveHosts(%{$params});
  $self->assert($result[0] eq "host-1001",
                "Wrong machine reserved: $result[0]");

  $params = { wait => 1,
              class => "FARM",
              numhosts => 2
            };

  @responses = ({ type => "success",
                  data => ["host-1001", "host-1002"],
                });
  @result = $rsvp->reserveHosts(%{$params});
  $self->assert($result[0] eq "host-1001",
                "Wrong machine reserved: $result[0]");
  $self->assert($result[1] eq "host-1002",
                "Wrong machine reserved: $result[1]");
}

######################################################################
##
sub testReserveHostsByClassWithRetry {
  my ($self) = @_;

  $params = { wait => 1,
              class => "FARM",
              numhosts => 1
            };

  @responses = ({ type => "ERROR",
                  temporary => 1,
                  message => "inserted fault" },
                { type => "success",
                  data => ["host-1001"] },
               );
  my @result = $rsvp->reserveHosts(%{$params});
  $self->assert($result[0] eq "host-1001",
                "Wrong machine reserved: $result[0]");
  # if we retried, responses should be empty
  $self->assert(!@responses, "Didn't retry, responses not empty");
}

######################################################################
##
sub testReserveHostsByClassWithPermanentError {
  my ($self) = @_;

  $params = { wait => 1,
              class => "FARM",
              numhosts => 1
            };

  @responses = ({ type => "ERROR",
                  message => "inserted fault" },
                { type => "success",
                  data => ["host-1001"] },
               );
  eval {
    $rsvp->reserveHosts(%{$params});
  };
  $self->assert($EVAL_ERROR, "reserveHosts didn't croak");
  $self->assert(scalar(@responses) == 1, "retried, responses empty");
}

######################################################################
##
sub testAppendClasses {
  my ($self) = assertNumArgs(1, @_);
  no warnings "redefine";

  local *Permabit::RSVP::getDistroInfo = sub { return "Fictional" };
  $self->assert_str_equals("\UFICTIONAL,FARM", $rsvp->appendClasses(undef));
  $self->assert_str_equals("\UFICTIONAL,FARM", $rsvp->appendClasses(''));

  local *Permabit::RSVP::getDistroInfo = sub { return "X" };
  $self->assert_str_equals("A,B,C,D,X,FARM", $rsvp->appendClasses("A,B,C,D"));
  $self->assert_str_equals("A,B,X,FARM", $rsvp->appendClasses(["A","B"]));
  $self->assert_str_equals("FARM,X", $rsvp->appendClasses("FARM"));
  $self->assert_str_equals("RHEL8,ALBIREO-PMI",
                           $rsvp->appendClasses(["RHEL8","ALBIREO-PMI"]));

  # Make sure sub-strings don't match
  $self->assert_str_equals("NOT_ALL,X,FARM", $rsvp->appendClasses("NOT_ALL"));
}

######################################################################
##
sub testAlbireoAppendClasses {
  my ($self) = assertNumArgs(1, @_);

  no warnings "redefine";
  local *Permabit::RSVP::getDistroInfo = sub { return "Fictional" };
  local *Permabit::RSVP::getReleaseInfo = sub { die(); };

  # should get host plus os class
  $self->assert_str_equals("ALBIREO,FICTIONAL,FARM",
                           $rsvp->appendClasses('ALBIREO'));
  # should get host
  $self->assert_str_equals("ALBIREO,FEDORA36,FARM",
                           $rsvp->appendClasses('ALBIREO,FEDORA36'));
  # should get host
  $self->assert_str_equals("ALBIREO,RHEL9,FARM",
                           $rsvp->appendClasses('ALBIREO,RHEL9'));
  # should get host
  $self->assert_str_equals("ALBIREO,RHEL9,FOO,FARM",
                           $rsvp->appendClasses('ALBIREO,RHEL9,FOO'));
  # should get os class and host.
  $self->assert_str_equals("ALBIREO,FOO,FICTIONAL,FARM",
                           $rsvp->appendClasses('ALBIREO,FOO'));

  local *Permabit::RSVP::getDistroInfo = sub { die() };
  local *Permabit::RSVP::getReleaseInfo = sub { return {
           version        => '5.0',
           suites         => ['fedora36', 'rhel9', 'fictional'],
           relTag         => 'albireo',
           defaultRelease => 'fedora36',
         }; };

  # should get default release
  $self->assert_str_equals("ALBIREO,FEDORA36,FARM",
                           $rsvp->appendClasses('ALBIREO'));
  # should stay the same, because both specified
  $self->assert_str_equals("ALBIREO,FEDORA36,FARM",
                           $rsvp->appendClasses('ALBIREO,FEDORA36'));
  # should stay the same, because both specified
  $self->assert_str_equals("ALBIREO,RHEL9,FARM",
                           $rsvp->appendClasses('ALBIREO,RHEL9'));
  # should stay the same, because both specified
  $self->assert_str_equals("ALBIREO,RHEL9,FOO,FARM",
                           $rsvp->appendClasses('ALBIREO,RHEL9,FOO'));
  # gets default release from getReleaseInfo
  $self->assert_str_equals("ALBIREO,FOO,FEDORA36,FARM",
                           $rsvp->appendClasses('ALBIREO,FOO'));
}


######################################################################
##
sub testReserveHostsByClassWithDist {
  my ($self) = assertNumArgs(1, @_);
  my @runningOnDist = (
                       'rhel9',
                       'fedora36',
                       'fclab',
                       'rhel7',
                       'rhel8',
                      );

  my @requestCases = (
                      { requested => '',
                        expected => "dist,FARM",
                      },
                      { requested => 'ALL',
                        expected => 'ALL',
                      },
                      { requested => 'FARM',
                        expected => 'FARM,dist',
                      },
                      { requested => 'VDO-PMI',
                        expected => 'VDO-PMI,dist',
                      },
                      { requested => 'VDO-PMI,ALL',
                        expected => 'VDO-PMI,ALL',
                      },
                      { requested => 'RHEL8,VDO-PMI',
                        expected => 'RHEL8,VDO-PMI',
                      },
                     );

  foreach my $dist (@runningOnDist) {
    no warnings "redefine";
    local *Permabit::RSVP::getDistroInfo = sub { return "FICTIONAL" };
    local *Permabit::RSVP::getReleaseInfo = sub { die(); };
    foreach my $request (@requestCases) {
      my $expectedResult = $request->{expected};

      $expectedResult =~ s/dist/FICTIONAL/;

      $params = { class => $request->{requested},
                  numhosts => 1,
                };
      @responses = ({type => "success",
                     data => ["host-1001"] },
                   );

      $rsvp->reserveHosts(%{$params});

      assertEq($expectedResult, $requestParams->{class},
               "Request for \"$request->{requested}\" "
               . "should have returned class $expectedResult; dist ($dist)");
    }
    undef;
  }
}

######################################################################
# Test for the inclusion of a host in a given class.
##
sub testIsInClass {
  my ($self) = @_;
  my @memberOfClasses     = ('ALL', 'ALBIREO', 'FARM', 'VFARM', 'RHEL9');
  my @notAMemberOfclasses = ('FOO', 'SARGE', 'GODOT', 'ALEWIFE');
  my @data = (['host-1001',
               'bob',
               join(', ', @memberOfClasses)
              ]);
  # host-1001 is in each of the above classes
  foreach my $class (@memberOfClasses) {
    @responses = ({type => "success",
                   data => [@data],
                  });
    $self->assert($rsvp->isInClass('host-1001', $class),
                  "Host not in class $class");
  }

  # host-1001 is in not in any of these classes
  foreach my $class (@notAMemberOfclasses) {
    @responses = ({type => "success",
                   data => [],
                  });
    $self->assert(!$rsvp->isInClass('host-1001', $class),
                  "Non-existent host erroneously in class $class");
  }
}

######################################################################
# Test for the inclusion of a host in MAINTENANCE.
##
sub testIsInMaintenance {
  my ($self) = @_;
  my @data = (['host-1001', 'bob', 'MAINTENENCE']);
  @responses = ({type => "success",
                 data => [@data],
                });
  $self->assert($rsvp->isInMaintenance('host-1001'),
                "Host is not in MAINTENENCE");
  @responses = ({type => "success",
                 data => [@data],
                });
  $self->assert(!$rsvp->isInMaintenance('bob'),
                "Host is in MAINTENENCE");
}

######################################################################
# Test host is in expected list of classes.
##
sub testGetClassInfo {
  my ($self) = @_;
  my $msg;
  my $host = 'host-1001';
  my @memberOfClasses     = ('ALL', 'ALBIREO', 'FARM', 'VFARM', 'RHEL9');
  my @notAMemberOfclasses = ('FOO', 'SARGE', 'GODOT');
  @responses = ({type => "success",
                 data => [[$host,'bob',join(', ', @memberOfClasses)]],
                });
  my @returnedClasses = $rsvp->getClassInfo($host);

  $msg = "Returned list not the same length as expected list";
  assertEqualNumeric(scalar(@memberOfClasses), scalar(@returnedClasses), $msg);

  $msg = "Returned list of classes does not equal Expected list";
  $self->assert_deep_equals(\@memberOfClasses, \@returnedClasses, $msg);

  $msg = "Somehow two unequal things are now equal: ";
  $self->assert_deep_not_equals(\@memberOfClasses, \@notAMemberOfclasses,
                                $msg);

  @responses = ({type => "success",
                 data => [['foo','bob',join(', ', @memberOfClasses)]],
                });
  eval {
    $rsvp->getClassInfo($host);
  };
  assertEvalErrorMatches(qr/Unable to get class info for $host/);

  @responses = ({type => "success",
                 data => [],
                });
  eval {
    $rsvp->getClassInfo($host);
  };
  assertEvalErrorMatches(qr/Unable to get class info for $host/);
}

######################################################################
# Assert that the host in $params is the same as in $requestParams
##
sub assertHost {
  my ($self, $params) = assertNumArgs(2, @_);

  $self->assert($requestParams->{host} eq $params->{host},
                "Wrong host in request: $requestParams->{host}");
}

######################################################################
# Run an athinfo command on a given host
##
sub _rsvpRunAthInfo {
  my ($self, $host, $command) = assertNumArgs(3, @_);

  if ($command eq "checkServer") {
    $numCheckServerCalls++;
    if ($checkServer->{$host} && scalar(@{$checkServer->{$host}})) {
      return (shift(@{$checkServer->{$host}}));
    }
    return ("success");
  } elsif ($command eq "ps") {
    $numPsCalls++;
    if ($ps->{$host} && scalar(@{$ps->{$host}})) {
      my $ret = shift(@{$ps->{$host}});
      if ($ret eq "FAILURE") {
        return ($ret, 'forced ps failure');
      }
      return ("USER PID %CPU %MEM...", $ret);
    }
    return ("");
  }

  return ("FAILURE", "unknown fake athinfo command '$command'");
}

######################################################################
# Utility method that returns the list of hosts specified by this
# release request.
##
sub _rsvpGetHostsToRelease {
  my ($self, $params) = assertNumArgs(2, @_);

  if ($params->{host}) {
    return ($params->{host});
  }

  delete $params->{all};
  return @hostsToRelease;
}

######################################################################
# Issue a request to the rsvp server and get a response.
#
# @param cmd            The name of the command being sent
# @param params         The parameters of that command
# @param checkResult    Whether or not to check the result of the command
#
# @return result of the command
##
sub _rsvpRequest {
  my ($self, $cmd, $params, $checkResult) = assertNumArgs(4, @_);
  $requestParams = $params;

  return shift @responses;
}

######################################################################
# Test default RSVP server
##
sub testGetDefaultRSVPServer {
  my ($self) = assertNumArgs(1, @_);
  my $server = $rsvp->_getDefaultRSVPServer();
  if (defined($server)) {
    $log->info($server);
  }
  assertDefined($server);
}

######################################################################
##
sub _asyncGetMaintenanceMessage {
  my ($self) = assertNumArgs(1, @_);
  Permabit::ConfiguredFactory::reset();
  $ENV{PERMABIT_PERL_CONFIG} = $self->{testConfigFile};
  $rsvp = new Permabit::RSVP(dhost => "bogus",
                             user  => "bob",
                             releaseRetryTimeout => 0,
                             reserveRetryTimeout => 0,
                             retryMultiplier => 1);
  my @oldClasses = qw(CLASS1 CLASS2);
  my $params = {
                message => "maintenance-message",
                description => "maint-description",
               };
  my $message = $rsvp->_getMaintenanceMessage($params,
                                              "the-host",
                                              \@oldClasses,
                                              "the-owner",
                                              "reservation/message");
  assertRegexpMatches(qr/the-host was moved to maintenance by bob/, $message);
  assertRegexpMatches(qr/--add CLASS1,CLASS2/, $message);
  assertRegexpMatches(qr/Searchable reservation message: reservation message/,
                      $message);
  return $message;
}

######################################################################
##
sub testMessage {
  my ($self) = assertNumArgs(1, @_);
  my @tests = (
               {
                name => "null path to tool dir",
                configEntry => "~",
                expectedResult => qr|[ \t]cleanFarm.sh|,
               },
               {
                name => "no toolDir entry",
                configEntry => undef,
                expectedResult => qr|[ \t]cleanFarm.sh|,
               },
               {
                name => "a path to tool dir",
                configEntry => "/path/to/tools",
                expectedResult => qr|[ \t]/path/to/tools//?cleanFarm.sh|,
                },
              );
  my $oldConfigPath = Permabit::ConfiguredFactory::_findConfigPath();
  my $oldConfig = `cat $oldConfigPath`;
  $oldConfig =~ s/^Permabit::RSVP:.*\n(^ .*\n)*//m;
  foreach my $test (@tests) {
    my ($fh, $tempfile) = tempfile();
    my $testConfig = <<EOF;
Permabit::RSVP:
  config:
    defaultRSVPServer: bogus-host.example.com
    emailDomain: foo.bar
EOF
    if (defined($test->{configEntry})) {
      $testConfig .= "    toolDir: $test->{configEntry}\n";
    }
    $self->{testConfigFile} = $tempfile;
    #$log->info("tweaked old config:\n$oldConfig");
    $log->info("testing with $test->{name}");
    print $fh $oldConfig, "\n", $testConfig;
    close($fh) || croak("error writing temp file $tempfile: $ERRNO");
    $log->debug("new config file:\n" . `cat $tempfile`);
    my $task = Permabit::AsyncSub->new(code => \&_asyncGetMaintenanceMessage,
                                       args => [ $self ])->start();
    my $message = $task->result();
    assertRegexpMatches($test->{expectedResult}, $message);
    unlink($self->{testConfigFile});
    delete $self->{testConfigFile};
  }
}

# Stubs... we can save away (some of) the arguments passed to verify
# the values desired in testing.

my $calls = {
             mail => [],
             jira => [],
            };

######################################################################
##
sub _fakeCreateJiraIssue {
  my ($project, $assignee, $component, $summary,
      $description, $reporter, $version) = assertNumArgs(7, @_);
  $log->debug("called _fakeCreateJiraIssue");
  my $jiraInfo = {
                  project     => $project,
                  assignee    => $assignee,
                  component   => $component,
                  summary     => $summary,
                  description => $description,
                  reporter    => $reporter,
                  version     => $version,
                 };
  push(@{$calls->{jira}}, $jiraInfo);
  return "JIRA-123";
}

######################################################################
##
sub _fakeCreateIssueDirectory {
  my ($issue) = assertNumArgs(1, @_);
  $log->debug("called _fakeCreateIssueDirectory");
  # ignore
}

######################################################################
##
sub _fakeSendMail {
  my ($src, $dest, $subject, $contentType, $message, @files)
    = assertMinArgs(5, @_);
  $log->debug("called _fakeSendMail");
  my $mailInfo = {
                  src => $src,
                  dest => $dest,
                  subject => $subject,
                  contentType => $contentType,
                  message => $message,
                  files => [ @files ],
                 };
  push(@{$calls->{mail}}, $mailInfo);
}

######################################################################
##
sub _fakeSendChat {
  my ($room, $recipient, $subject, $msg) = assertNumArgs(4, @_);
  $log->debug("called _fakeSendChat");
  # ignore
}

######################################################################
##
sub _asyncCallNotify {
  my ($self, $testParams) = assertNumArgs(2, @_);
  my @oldClasses = qw(CLASS1 CLASS2);
  Permabit::ConfiguredFactory::reset();
  $ENV{PERMABIT_PERL_CONFIG} = $self->{testConfigFile};
  $rsvp = new Permabit::RSVP(dhost => "bogus",
                             user  => "bob",
                             releaseRetryTimeout => 0,
                             reserveRetryTimeout => 0,
                             retryMultiplier => 1);
  # Only override these in the subprocess.
  {
    no warnings;
    *Permabit::RSVP::createJiraIssue = \&_fakeCreateJiraIssue;
    *Permabit::RSVP::createIssueDirectory
      = \&_fakeCreateIssueDirectory;
    *Permabit::RSVP::sendMail = \&_fakeSendMail;
    *Permabit::RSVP::sendChat = \&_fakeSendChat;
  }
  my $issue = $rsvp->_notifyMaintenance($testParams, "test-host",
                                        \@oldClasses);
  assertEq("JIRA-123", $issue);
  assertEqualNumeric(1, scalar(@{$calls->{jira}}));
  return $calls;
}

######################################################################
##
sub _testNotifyCommon {
  my ($self, $config, $params, $expectedJiraUser) = assertNumArgs(4, @_);
  my ($fh, $tempfile) = tempfile();
  $self->{testConfigFile} = $tempfile;
  print $fh $config;
  close($fh) || croak("error writing temp file $tempfile: $ERRNO");
  $log->debug("new config file:\n" . `cat $tempfile`);

  my $task = Permabit::AsyncSub->new(code => \&_asyncCallNotify,
                                     args => [ $self, $params ])->start();
  my $result = $task->result();
  unlink($self->{testConfigFile});
  delete $self->{testConfigFile};
  # There should always be one ticket opened, though the reporter name
  # can vary. Email will vary, and should be checked per call.
  assertEqualNumeric(1, scalar(@{$result->{jira}}));
  assertEq($expectedJiraUser, $result->{jira}->[0]->{reporter});
  return $result;
}

######################################################################
##
sub testNotify {
  my ($self) = assertNumArgs(1, @_);
  my $oldConfigPath = Permabit::ConfiguredFactory::_findConfigPath();
  my $oldConfig = `cat $oldConfigPath`;
  $oldConfig =~ s/^Permabit::RSVP:.*\n(^ .*\n)*//m;

  # Testing: emailDomain, jiraUserWhenForce, force.
  my $testConfig = <<EOF;
Permabit::RSVP:
  config:
    defaultRSVPServer: bogus-host.example.com
    emailDomain: mail.example.com
    toolDir: ~
EOF
  my $params = {
                project     => 'OPS',
                component   => 'Maintenance',
                codename    => 'current',
                description => '',
                assignee    => 'me',
                force       => 0,
                message     => 'maintenance message',
               };

  # No owner in RSVP
  my $result = $self->_testNotifyCommon("$oldConfig\n$testConfig", $params,
                                        "bob");
  assertEqualNumeric(0, scalar(@{$result->{mail}}));

  # With owner
  @responses = ({
                 type => "success",
                 message => "party on, dude",
                 data => [['test-host', 'some-owner', 'MAINTENANCE']]
                });
  $result = $self->_testNotifyCommon("$oldConfig\n$testConfig", $params,
                                     "bob");
  assertEqualNumeric(1, scalar(@{$result->{mail}}));
  my $mail = $result->{mail}->[0];
  assertEq("bob\@mail.example.com", $mail->{src});
  assertEq("some-owner\@mail.example.com", $mail->{dest}->[0]);

  # With owner, force=1, but no user override setting
  $params->{force} = 1;
  @responses = ({
                 type => "success",
                 message => "party on, dude",
                 data => [['test-host', 'some-owner', 'MAINTENANCE']]
                });
  $result = $self->_testNotifyCommon("$oldConfig\n$testConfig", $params,
                                     "bob");
  # force suppresses email
  assertEqualNumeric(0, scalar(@{$result->{mail}}));

  # With owner, force=1, with user override setting
  $testConfig .= "    jiraUserWhenForce: magicJiraUser\n";
  @responses = ({
                 type => "success",
                 message => "party on, dude",
                 data => [['test-host', 'some-owner', 'MAINTENANCE']]
                });
  $result = $self->_testNotifyCommon("$oldConfig\n$testConfig", $params,
                                     "magicJiraUser");
  # force suppresses email
  assertEqualNumeric(0, scalar(@{$result->{mail}}));
}

1;
