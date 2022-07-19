##
# Check that /var/crash is empty.
#   under --fix: Moves all crash files to a directory in
#                /permabit/not-backed-up
# $Id$
##
package CheckServer::Test::VarCrash;

use strict;
use warnings FATAL => qw(all);

use English qw(-no_match_vars);
use File::Find;

use Permabit::Assertions qw(assertNumArgs);

use CheckServer::Constants qw(@IGNORE_CRASH_PATTERNS);

use base qw(CheckServer::Test);

########################################################################
# @inherit
##
sub test {
  my ($self) = assertNumArgs(1, @_);
  if (! -d  '/var/crash') {
    return;
  }

  my $dst = join('-',
                 "/permabit/not-backed-up/crash/" . $self->hostname(),
                 `date +'%Y-%m-%dT%H:%M:%S'`);
  chomp($dst);

  my $preamble = "mkdir -p $dst && chmod g+wrxs $dst";
  my $fail     = 0;

  # Some applications leave these.
  my @appCrashFiles = glob("/var/crash/*crash");

  # Filter out any known crashes we don't care about.
  foreach my $ignoreRegexp (@IGNORE_CRASH_PATTERNS) {
    @appCrashFiles = grep($_ !~ $ignoreRegexp, @appCrashFiles);
  }

  if (scalar(@appCrashFiles) > 0) {
    $fail = 1;
    $self->addFixes("$preamble && mv /var/crash/\*crash $dst/");
  }

  # The following is a complicated invocation of File::Find as there are
  # diverse uses which get made of /var/crash.
  our @kernelCrashDirs;
  my $wanted = sub {
    # Note: not y3K compliant.
    # Covers SQUEEZE, WHEEZY and RHEL formatted crashdirs.
    # using a
    #
    if (/^(127\.0\.0\.1-)?2[\d\-:]+\z/s) {
      push(@kernelCrashDirs, $File::Find::name);
      print "Found $File::Find::name\n";
    }
  };

  File::Find::find({wanted => $wanted}, '/var/crash');
  if (scalar(@kernelCrashDirs) > 0) {
    $fail = 1;
    $self->addFixes(map({ $_ = "$preamble && mv $_ $dst" } @kernelCrashDirs));
  }

  if ($fail) {
    $self->fail(join(' ', "Crash files or directories in /var/crash:",
                     @kernelCrashDirs, @appCrashFiles));
  }
}

1;

