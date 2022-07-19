##
# Test the LastrunUpdater Object
#
# $Id$
##
package testcases::LastrunUpdater_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Permabit::Assertions qw(assertNumArgs);
use Permabit::LastrunUpdater;
use Permabit::SystemUtils qw(assertCommand assertSystem runSystemCommand);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my %DEFAULT_RULES = (
  perl  => sub {
    my ($source, $host, $dir) = assertNumArgs(3, @_);
    assertCommand($host, "touch $dir/foo");
  },
  tools => sub {
    my ($source, $host, $dir) = assertNumArgs(3, @_);
    assertCommand($host, "touch $dir/baz");
  });

##################################################################
##
sub set_up {
  my ($self) = assertNumArgs(1,@_);
  $self->{testRoot} = sprintf("/u1/%s-%s/%s/%s",
                      ref($self) =~ m/.*::([^:]+)$/,
                      $self->{user},
                      $PID,
                      $self->fullName() =~ m/.*::([^:]+)$/);
  $log->info("Our temp dir is: $self->{testRoot}");
  assertSystem("mkdir -p $self->{testRoot}");
  $self->{updater}
    = Permabit::LastrunUpdater->new(baseDir => $self->{testRoot},
                                    rules   => \%DEFAULT_RULES,
                                    source  => "");
}

##################################################################
##
sub tear_down {
  my ($self) = assertNumArgs(1,@_);
  assertSystem("sudo rm -rf $self->{testRoot}/*");
  runSystemCommand("sudo rmdir -p $self->{testRoot}");
  delete $self->{updater};
}

##################################################################
##
sub testExtractDate {
  my ($self) = assertNumArgs(1,@_);
  my $u = $self->{updater};
  $self->assert_deep_equals([qw(1776 07 04)],
                            [$u->_extractDate('1776-07-04-12-00')]);
}

##################################################################
##
sub testGetBuildDirs {
  my ($self) = assertNumArgs(1,@_);
  foreach my $dir (qw(1776-07-04-12-00 by-hand lastrun 2000-10-11-11-59
                      1999-01-24 12-01-01-01-01 2012-1-12-09-10
                      2015-10-21-04-00)) {
    mkdir("$self->{testRoot}/$dir") || die("couldn't mkdir $dir: $ERRNO");
  }
  my $u = $self->{updater};
  my @expected = map { "$self->{testRoot}/$_" }
                     qw(2015-10-21-04-00 2000-10-11-11-59 1776-07-04-12-00);
  $self->assert_deep_equals(\@expected,
                            [$u->_getBuildDirs($self->{testRoot})]);
}

##################################################################
##
sub testIsExpired {
  my ($self) = assertNumArgs(1,@_);
  my $u = $self->{updater};
  $u->{now} = '2012-09-02-08-25';
  $u->{age} = 4;
  # The current implementation of _isExpired() ignores the
  # time portion of the date-timestamp so don't bother testing
  # that.
  $self->assert(!$u->_isExpired('2012-09-02-08-25'));
  $self->assert(!$u->_isExpired('2012-09-04-08-24'));
  $self->assert(!$u->_isExpired('2012-09-01-08-24'));
  $self->assert(!$u->_isExpired('2012-08-31-08-24'));
  $self->assert(!$u->_isExpired('2012-08-30-08-24'));
  $self->assert(!$u->_isExpired('2012-08-29-08-24'));
  $self->assert($u->_isExpired('2012-08-28-08-24'));
  $self->assert($u->_isExpired('2011-12-01-08-24'));
}

##################################################################
##
sub testEnd2End {
  my ($self) = assertNumArgs(1,@_);
  my $u = $self->{updater};
  $u->{age} = 4;
  $u->{count} = 3;

  # Test that we always keep at least <count> number of build dir
  # around even if they are older than <age>
  $u->{now} = '2012-09-02-08-25';
  $u->runRules();
  $u->{now} = '2012-09-02-08-26';
  $u->runRules();
  $u->{now} = '2012-09-02-08-27';
  $u->runRules();
  $u->{now} = '2012-09-07-08-27';
  $u->runRules();
  $u->{now} = '2012-09-09-08-26';
  $u->runRules();

  $u->updateLastrun();

  $u->pruneOldDirs();

  my @expected = qw(2012-09-09-08-26 2012-09-07-08-27 2012-09-02-08-27);
  $self->assert_deep_equals([map {"$self->{testRoot}/$_"} @expected],
                            [$u->_getBuildDirs("$u->{baseDir}")]);

  # Now test that we can have more than <count> build dirs around
  # as long as they are not older than <age>
  $u->{now} = '2012-09-12-08-26';
  $u->runRules();
  $u->{now} = '2012-09-12-08-27';
  $u->runRules();
  $u->{now} = '2012-09-12-08-28';
  $u->runRules();

  $u->updateLastrun();

  $u->pruneOldDirs();

  @expected = qw(2012-09-12-08-28 2012-09-12-08-27 2012-09-12-08-26
                 2012-09-09-08-26);
  $self->assert_deep_equals([map {"$self->{testRoot}/$_"} @expected],
                            [$u->_getBuildDirs("$u->{baseDir}")]);
}

1;
