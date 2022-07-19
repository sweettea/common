######################################################################
# Utility for copying files around
#
# $Id$
##
package Permabit::FileCopier;

use strict;
use warnings FATAL => qw(all);

use Carp;
use English qw(-no_match_vars);
use File::stat;
use Log::Log4perl;
use Storable qw(dclone);
use Sys::Hostname;
use Permabit::Assertions qw(assertNumArgs);
use Permabit::Constants;
use Permabit::ProcessUtils qw(delayFailures);
use Permabit::SystemUtils qw(assertCommand assertSystem runCommand);
use Permabit::Utils qw(
  makeFullPath
  mapConcurrent
  retryUntilTimeout
  shortenHostName
);

# Log4perl Logging object
my $log = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
# Default files to copy
##
my @DEFAULT_SOURCE_FILES =
  (
   {
    files => ['perl/bin'],
    dest  => 'src/perl',
   },
   {
    files => ['perl/lib'],
    dest  => 'src/perl',
   },
   {
    files => ['perl/Permabit'],
    dest  => 'src/perl',
   },
   {
    files => ['perl/Pdoc'],
    dest  => 'src/perl',
   },
   {
    files => ['c++/third/fsx', 'src/c++/third/fsstress'],
    dest  => 'src/c++/third',
   },
  );


##
# @paramList{newProperties}
my %properties =
  (
   #########################
   # constructor arguments
   #########################

   # @ple the local source tree
   mainBase => undef,

   # @ple machine to copy to. if machine is 'nfs', assume targetBinDir
   # is nfs accessible via localhost
   machine => "nfs",

   # @ple extra options to pass on to rsync
   rsyncOptions => "",

   # @ple the files to copy
   sourceFiles => \@DEFAULT_SOURCE_FILES,

   # @ple the directory to copy things over to
   targetBinDir => undef,

   #########################
   # member variables
   #########################

   #a has recording whether a type of file has been
   #copied over.
   _filesCopiedOver => { },
  );
##

######################################################################
# Instantiate a new FileCopier.
#
# @params{newProperties}
##
sub new {
  my $pkg = shift(@_);
  my $self = bless
    {
     # Clone %properties so original isn't modified
     %{ dclone(\%properties) },
     @_,                        # override defaults
    }, $pkg;

  return $self;
}

#####################################################################
# Copy files according to specification.
#
# @param base   base directory of files
# @param files  a hashref file descriptions
##
sub _copyFiles {
  my ($self, $base, $files) = assertNumArgs(3, @_);
  mapConcurrent {
    my $k = $_;
    my @f = map { (($_ =~ m|^/|) ? '' : ($base . "/")) . $_ } @{$k->{files}};
    @f  = map { glob($_) } @f;
    if ($k->{optional} || $k->{onlyOne}) {
      @f = grep { -f $_ } @f;
    }
    if ($k->{onlyOne} && scalar(@f) > 1) {
      @f = sort { stat($b)->mtime <=> stat($a)->mtime } @f;
      @f = ($f[0]);
    }
    if (@f) {
      $self->_rsyncFiles(join(" ", @f),
                         makeFullPath($self->{targetBinDir}, $k->{dest}));
    }
  } @{$files};
}

#####################################################################
# Copy src files from mainBase.
##
sub copySrcFiles {
  my ($self) = assertNumArgs(1, @_);
  $self->_copyFiles($self->{mainBase}, $self->{sourceFiles});
}

######################################################################
# Return true if file of a given type has been copied over
##
sub _filesCopied {
  my ($self, $type) = assertNumArgs(2, @_);
  if (defined $self->{_filesCopiedOver}->{$type}) {
    return 1;
  }
  return 0;
}

######################################################################
##
sub _setFilesCopied {
  my ($self, $type) = assertNumArgs(2, @_);
  $self->{_filesCopiedOver}->{$type} = 1;
}

######################################################################
# copy $files to
# $self->{machine}:$dir using rsync -- if machine is 'nfs', assume
# target path is nfs accessible via localhost
##
sub _rsyncFiles {
  my ($self, $files, $dir) = assertNumArgs(3, @_);

  if ($self->_filesCopied("$files")) {
    return;
  }
  $log->debug("Rsyncing over " . $files . " to $self->{machine}:$dir");
  my $hostname  = shortenHostName(hostname());
  my $localhost = ($self->{machine} eq "localhost"
                   || $self->{machine} eq "nfs"
                   || $self->{machine} eq $hostname);

  my $machine = $localhost ? "localhost" : $self->{machine};
  my $machineColon = $localhost ? "" : "$machine:";

  assertCommand($machine, "mkdir -p $dir");

  my $lockDir = makeFullPath($dir, "rsync-lock");
  $log->debug("lockdir is $machineColon$lockDir");
  my $locker = sub {
    return runCommand($machine, "mkdir $lockDir")->{status} == 0;
  };
  retryUntilTimeout($locker, "Cannot lock $lockDir", 15 * $MINUTE, 5);

  # rsync only copies files over if they have changed.
  # It checks this by stat-ing the source and target files.
  my $command = "rsync ";
  if (!$localhost) {
    $command .= "-e ssh ";
  }
  $command .= ("-a --copy-unsafe-links --delete "
               . "--exclude '*.o' --exclude '*.d' "
               . "$self->{rsyncOptions} $files $machineColon$dir");
  # Ensure that we always remove the lock even when the rsync fails.
  delayFailures(sub { assertSystem($command); },
                sub {
                  assertCommand($machine, "rmdir $lockDir || rm -rf $lockDir");
                });

  $self->_setFilesCopied("$files");
}

1;
