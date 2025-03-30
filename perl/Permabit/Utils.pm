##
# Utility functions for use within Permabit
#
# @synopsis
#
#     use Permabit::Utils qw(sendMail getRandomHandle);
#
#     sendMail(<sender>@<sender-domain>,<recipient>@<recipient-domain>,
#              "Hi there!", undef, "Just a note");
#     sendMail(<sender>@<sender-domain>,<recipient>@<recipient-domain>,
#              "Hi there!",
#              "text/html; charset=ISO-8859-1", "<b>Just a note</b>",
#              "/tmp/foo.dat");
#
#     my $r = getRandomHandle();
#
# @description
#
# C<Permabit::Utils> provides utility methods for use elsewhere in the
# Permabit system.  It provides a functional interface to these
# methods due to their static nature.
#
# $Id$
##
package Permabit::Utils;

use strict;
use warnings FATAL => qw(all);
use autodie qw(open close opendir);

use Carp qw(carp cluck confess croak);
use Config;
use English qw(-no_match_vars);
use File::Basename;
use File::Spec;
use Mail::Mailer;
use POSIX qw(ceil strftime);
use Regexp::Common qw(net);
use Socket;
use Storable qw(dclone);
use Time::HiRes qw(gettimeofday sleep usleep);
use Time::Local qw(timelocal);
use YAML;

use Permabit::Assertions qw(
  assertDefined
  assertLTNumeric
  assertMinArgs
  assertMinMaxArgs
  assertNumArgs
  assertNumDefinedArgs
  assertRegexpMatches
  assertTrue
);
use Permabit::Constants;

use base qw(Exporter);

our @EXPORT_OK = qw(
  addToHash
  addToList
  arrayDifference
  arraySameMembers
  attention
  canonicalizeHostname
  ceilMultiple
  dateStr
  findAllTests
  findExecutable
  findFile
  getRandomElement
  getRandomElements
  getRandomGaussian
  getRandomIdx
  getRandomIdx2
  getRandomSeed
  getRandomVolume
  getRandomVolumeID
  getRandomWeightedIdx
  getRandomWeightedIdx2
  getScamVar
  getSignalNumber
  getUserName
  getYamlHash
  hashExtractor
  hashToArgs
  hostToIP
  hoursToMS
  inNfs
  makeFullPath
  makeRandomToken
  mapConcurrent
  mergeToHash
  minutesToMS
  onSameNetwork
  openMaybeCompressed
  parseBytes
  parseISO8061toMillis
  reallySleep
  redirectOutput
  removeArg
  removeFromList
  restoreOutput
  rethrowException
  retryUntilTimeout
  secondsToMS
  selectFromWeightedMap
  selectFromWeightedMap2
  sendChat
  sendMail
  shortenHostName
  sizeToLvmText
  sizeToText
  spliceRandomElement
  timeout
  timeToText
  waitForInput
  yamlStringToHash
);

our $VERSION = 1.0;

our $IMPLEMENTATION;

sub _getImplementation {
  if (!defined($IMPLEMENTATION)) {
    # We have to do this here, and not at package scope in order to avoid
    # circular dependencies with ConfiguredFactory.
    eval("use Permabit::Utils::Implementation");
    $IMPLEMENTATION = Permabit::Utils::Implementation->new();
  }

  return $IMPLEMENTATION;
}

######################################################################
# Add key-value pairs to a hashref
#
# @param hashRef  The hash ref to add the values to
# @param args     Any remaining arguments will be added as key-value pairs
#                 to the hash.
##
sub addToHash {
  my ($hashRef, %kvpairs) = assertMinArgs(1, @_);
  foreach my $key (keys(%kvpairs)) {
    $hashRef->{$key} = $kvpairs{$key};
  }
}

######################################################################
# Add elements to a listref
#
# @param arrayRef  The list ref to add the values to
# @param pos       If set to 'start', the values will be added to the
#                  beginning of the list, otherwise to the end.
# @param args      Any remaining arguments will be added to the list in order
##
sub addToList {
  my ($arrayRef, $pos, @args) = assertMinArgs(2, @_);
  if ($pos eq 'start') {
    unshift(@{$arrayRef}, @args);
  } else {
    push(@{$arrayRef}, @args);
  }
}

######################################################################
# Calculate the difference between two arrays with unique elements.  In
# other words, return all the elements of the first array that don't exist
# in second array.
#
# @param  array1  The first array
# @param  array2  The second array
#
# @return array1 - array2
##
sub arrayDifference {
  my ($array1, $array2) = assertNumArgs(2, @_);
  my %h2 = map { $_ => 1} @$array2;
  return [ grep { !$h2{$_} } @$array1 ];
}

#############################################################################
# Check if two arrays have the same members.  Every member of the first array
# must also be a member of the second array, and vice versa.  A value can be
# duplicated in either array.
#
# @param  array1  The first array
# @param  array2  The second array
#
# @return true if the arrays contain the same members, otherwise false
##
sub arraySameMembers {
  my ($array1, $array2) = assertNumArgs(2, @_);
  my %h1 = map { $_ => 1 } @$array1;
  foreach my $e (@$array2) {
    if (!defined($h1{$e})) {
      return 0;
    }
    $h1{$e} = 0;
  }
  return !(grep { $_ } (values(%h1)));
}

######################################################################
# Return the canonicalized version of this hostname, if we can find
# one.
#
# @param hostname  The hostname to canonicalize
#
# @return the canonical hostname
##
sub canonicalizeHostname {
  return _getImplementation()->canonicalizeHostname(@_);
}

##########################################################################
# Returns string with current time in permabit pseudo-ISO
# (yyyy-mm-ddThh.mm.ss) format.
#
# @oparam when  seconds since epoch
##
sub dateStr {
  my ($when) = assertMinMaxArgs([undef], 0, 1, @_);
  if (!defined($when)) {
    $when = time;
  }
  return strftime("%Y-%m-%dT%H.%M.%S", localtime($when));
}

######################################################################
# Provides a trivial way to send a mail message.  It uses the
# C<Mail::Mailer> module to implement this functionality, and exists
# primarily to provide a simpler interface to the most commonly used
# parts of that module.
#
# @param  src         Email addresses for the sender
# @param  dest        Email addresses for the recipient
# @param  subject     Subject line of the email (under 70 characters)
# @param  contentType The content type of the email body
# @param  message     Body of the email.
# @oparam files       Names of files which should be embedded at the end of
#                     the message.
#
# @croaks if I<FILES> can't be opened or Mail::Mailer::open() fails
##
sub sendMail {
  my ($src, $dest, $subject, $contentType, $message, @files)
    = assertMinArgs(5, @_);

  # Generate the mail. Explicitly set the domain, since the domain
  # autodetection currently generates errors (do so twice, to remove
  # stupid error about using value only once).
  my $mailer = new Mail::Mailer('sendmail');
  $Mail::Util::domain = _getImplementation()->{mail}->{domain};
  $Mail::Util::domain = _getImplementation()->{mail}->{domain};

  my %headers = ( From    => $src,
                  To      => $dest,
                  Subject => $subject );
  if (defined($contentType)) {
    $headers{'Content-Type'} = $contentType;
  }
  $mailer->open(\%headers) || croak("Can't send mail: $ERRNO\n");
  print $mailer "$message\n\n";

  my $filename;
  local $INPUT_RECORD_SEPARATOR = undef;
  foreach my $filename (grep { defined($_) } @files) {
    # slurp in the given file
    open(my $mailbody, "<",  $filename)
      || croak "Can't open file $filename: $ERRNO\n";

    my $filebody = <$mailbody>;
    close($mailbody);

    print $mailer "Embedding file ($filename):\n";
    print $mailer "---------------------------\n";
    print $mailer $filebody;
    print $mailer "\n---------------------------\n";
  }

  #send it
  $mailer->close();
}

##########################################################################
# Return a 8 byte packed value full of random data
##
sub getRandomVolume {
  my @data = ();
  foreach (1 .. 8) {
    push(@data, int(rand(256)));
  }
  return pack("C8", @data);
}

##########################################################################
# Return a 8 byte packed value full of random data,
# in hex format
##
sub getRandomVolumeID {
  return unpack("H16", getRandomVolume());
}

######################################################################
# Return the value of a scam setting for this host
#
# @param   $var The scam variable to retrieve the value for.
#
# @return       The the value of the retrieved variable. Empty string if no
#               scam value is set.
##
sub getScamVar {
  my ($var) = assertNumArgs(1, @_);
  my $scam = `/sbin/scam $var`;
  chomp($scam);
  return $scam;
}

######################################################################
# Get the number for a signal. Will croak if the signal is unknown.
#
# @param name  The name of the signal
#
# @return The number of the specified signal
##
sub getSignalNumber {
  my ($name)  = assertNumArgs(1, @_);
  my $counter = 0;
  foreach my $signalName (split(' ', $Config{sig_name})) {
    if ($name eq $signalName) {
      return $counter;
    }
    $counter++;
  }

  croak("Unknown signal name: $name");
}

######################################################################
# Select a random key from a map in which the values are the weight
# for their keys.
#
# @param map    The weighted map to chose from
#
# @return The selected key from that map.
##
sub selectFromWeightedMap {
  my ($map) = assertNumArgs(1, @_);

  my $weighted = getRandomWeightedIdx(values(%$map));
  return (keys(%$map))[$weighted];
}

######################################################################
# Select a random key from a map in which the values are the weight
# for their keys.
#
# Re-implemented because rand has lumpy value distribution but we
# do not want to change other tests.
#
# @param map    The weighted map to chose from
#
# @return The selected key from that map.
##
sub selectFromWeightedMap2 {
  my ($map) = assertNumArgs(1, @_);

  my $weighted = getRandomWeightedIdx2(values(%$map));
  return (keys(%$map))[$weighted];
}

######################################################################
# Get a random element from an arrayref or hashref
#
# @param ref  The reference to the array or hash from which to select
#
# @return Depends upon the type of reference passed in as the argument.
#         For an arrayRef, returns a randomly selected scalar element.
#         For a hashRef, returns a randomly selected (key, value) pair.
#
# @confesses if I<REF> is neither an array nor a hash reference
##
sub getRandomElement {
  my ($ref) = assertNumArgs(1, @_);
  if (ref($ref) eq "ARRAY") {
    return $ref->[getRandomIdx($ref)];
  } elsif (ref($ref) eq "HASH") {
    my $key = getRandomElement([keys(%$ref)]);
    return ($key, $ref->{$key});
  } else {
    confess("Argument to getRandomElement must be an array or hash reference");
  }
}

######################################################################
# Get random elements from an arrayref
#
# @param arrayRef The array from which to select
# @param number   How many elements to return
#
# @return List of elements randomly selected from the array ref.
##
sub getRandomElements {
  my ($arrayRef, $number) = assertNumArgs(2, @_);
  my @array = @$arrayRef;
  my @value;
  while ((--$number >= 0) && scalar(@array)) {
    push(@value, splice(@array, getRandomIdx(\@array), 1));
  };
  return @value;
}

######################################################################
# Splice a random element from an arrayref
#
# @param arrayRef  The array from which to select and splice
#
# @return The randomly selected element
##
sub spliceRandomElement {
  my ($arrayRef) = assertNumArgs(1, @_);
  return splice(@$arrayRef, getRandomIdx($arrayRef), 1);
}

######################################################################
# Get a random Gaussian value.
#
# The algorithm here is the Marsaglia polar method, which actually
# generates two normally distributed random values. We only care about
# one of them, however.
# http://en.wikipedia.org/wiki/Marsaglia_polar_method
#
# @oparam mean  The mean of the distribution. Default is 0.
# @oparam sigma The standard deviation. Default is 1.
#
# @return a random Gaussian value with the specified mean and standard
#         deviation
##
sub getRandomGaussian {
  my ($mean, $sigma) = assertMinMaxArgs([0, 1], 0, 2, @_);
  my ($x, $y, $s);
  # Choose a random point in the unit circle
  do {
    $x = 2 * rand() - 1;
    $y = 2 * rand() - 1;
    $s = $x*$x + $y*$y;
  } while ( $s >= 1 );
  # Do the thing.
  my $g = $x * sqrt( (-2 * log($s))  / $s);

  # Scale and translate the result to the requested parameters
  return $g * $sigma + $mean;
}

######################################################################
# Return a random element index from an arrayref
#
# @param arrayRef The array from which to select an index.
#
# @return An element index randomly selected from the array ref.
##
sub getRandomIdx {
  my ($arrayRef) = assertNumArgs(1, @_);
  my @array = @{$arrayRef};
  return int(rand(scalar(@array)));
}

######################################################################
# Get a random array index into the specified array, with unequal
# weighting based on the weights in the array.
#
# @param weights An array of weights for integers starting at 0. The
#                 weights should add up to 1.
#
# @return A random integer between 0 and $#weights
##
sub getRandomWeightedIdx {
  my (@weights) = assertMinArgs(1, @_);
  my $r = rand(1);
  my $sum = 0.0;
  for (my $i = 0; $i < scalar(@weights); $i++) {
    if ($sum >= $r) {
      return $i - 1;
    }
    $sum += $weights[$i];
  }
  return scalar(@weights) - 1;
}

######################################################################
# Get a random array index into the specified array, with unequal
# weighting based on the weights in the array.
# Re-implemented because rand has lumpy value distribution but we
# do not want to change other tests.
#
# @param weights An array of weights for integers starting at 0. The
#                 weights should add up to 1.
#
# @return A random integer between 0 and $#weights
##
sub getRandomWeightedIdx2 {
  my (@weights) = assertMinArgs(1, @_);
  my ($seconds, $microseconds) = gettimeofday;
  my $r = $microseconds % 100.00;
  $r = $r / 100.00;
  my $sum = 0.0;
  for (my $i = 0; $i < scalar(@weights); $i++) {
    if ($sum >= $r) {
      return $i - 1;
    }
    $sum += $weights[$i];
  }
  return scalar(@weights) - 1;
}

######################################################################
# Return a random element index from an arrayref,
# Re-implemented because rand has lumpy value distribution but we
# do not want to change other tests.
#
# @param arrayRef The array from which to select an index.
#
# @return An element index randomly selected from the array ref.
##
sub getRandomIdx2 {
  my ($arrayRef) = assertNumArgs(1, @_);
  my @array = @{$arrayRef};
  my ($seconds, $microseconds) = gettimeofday;
  return int($microseconds) % scalar(@array);
}

######################################################################
# Generate a good value to use for seeding the RNG, as given in the
# perlfunc man page.
#
# @return - A value to use to seed the RNG.
##
sub getRandomSeed {
  return (time ^ $$ ^ unpack "%L*", `ps axww | gzip`);
}

######################################################################
# Return the user name of the current user.
#
# @return the current user name
# @croaks if user name could not be derived
##
sub getUserName {
  return getpwuid($REAL_USER_ID) || $ENV{LOGNAME}
    || croak("Unable to get username");
}

######################################################################
# Shorten hostnames for convenience and log reduction. Implementation specific.
# The shortened form of hostname must still resolve.
#
# @param h                The hostname to shorten
#
# @return the host name in short form
##
sub shortenHostName {
  return _getImplementation()->shortenHostName(@_);
}

######################################################################
# Convert a number of bytes to a human-readable format (e.g., 3K 42M 5T).
#
# @param  bytes         The number of bytes.
# @oparam precision     The number of digits of precision to include,
#                       defaults to 2.
#
# @return A human-readable string for that number of bytes.
##
sub sizeToText {
  my ($bytes, $precision) = assertMinMaxArgs([2], 1, 2, @_);
  if ($bytes > $EB) {
    return sprintf("%.${precision}f EB", ($bytes / $EB));
  } elsif ($bytes > $PB) {
    return sprintf("%.${precision}f PB", ($bytes / $PB));
  } elsif ($bytes > $TB) {
    return sprintf("%.${precision}f TB", ($bytes / $TB));
  } elsif ($bytes > $GB) {
    return sprintf("%.${precision}f GB", ($bytes / $GB));
  } elsif ($bytes > $MB) {
    return sprintf("%.${precision}f MB", ($bytes / $MB));
  } elsif ($bytes > $KB) {
    return sprintf("%.${precision}f KB", ($bytes / $KB));
  } else {
    return "$bytes B";
  }
}

######################################################################
# Convert a number into LVM size syntax
# A size suffix of B for bytes, S for sectors, K for kilobytes,
# M for megabytes, G for gigabytes, T for terabytes, P for petabytes, or
# E for exabytes is added if necessary.
#
# @param bytes    the number to convert, with optional suffix.
#
# @return         the input number coerced to lvm syntax.
##
sub sizeToLvmText {
  my ($bytes) = assertNumArgs(1, @_);

  if ($bytes =~ /^ *([\d\.]+) *[EePpTtGgMmKkSsBb] *$/) {
    return $bytes;
  }

  if (($bytes % $EB) == 0) {
    my $size = $bytes / $EB;
    return "${size}E";
  }
  if (($bytes % $PB) == 0) {
    my $size = $bytes / $PB;
    return "${size}P";
  }
  if (($bytes % $TB) == 0) {
    my $size = $bytes / $TB;
    return "${size}T";
  }
  if (($bytes % $GB) == 0) {
    my $size = $bytes / $GB;
    return "${size}G";
  }
  if (($bytes % $MB) == 0) {
    my $size = $bytes / $MB;
    return "${size}M";
  }
  if (($bytes % $KB) == 0) {
    my $size = $bytes / $KB;
    return "${size}K";
  }
  if (($bytes % $SECTOR_SIZE) == 0) {
    my $size = $bytes / $SECTOR_SIZE;
    return "${size}S";
  }
  return "${bytes}B";
}

######################################################################
# Parse the given size string into the number of Bytes it represents.  Use
# (case insensitive) "EB" for exbibytes", "PB" for pebibytes, "TB" for
# tebibytes, "GB" for gibibytes, "MB" for mebibytes, "KB" for kibibytes,
# S for sectors, and "B" or nothing, for Bytes.
#
# For example: parseBytes("1KB") returns 1024.
#              and parseBytes(2048) returns 2048.
#
# This method allows upper or lowercase specifier.
# Valid Examples: 1 KB, 1KB, 1kb, 1kB, and 1k.
#
# @param bytesStr    The size to parse, with the unit appended
#
# @return the number of bytes the input represented
# @croaks if argument cannot be parsed
##
sub parseBytes {
  my ($bytesStr) = assertNumArgs(1, @_);

  $bytesStr =~ /^ *([\d\.]+) *(\w)?\w* *$/;
  assertDefined($1, "Could not parse: $bytesStr");

  my %ABBREV_TO_BYTES = (
    "e" => $EB,
    "p" => $PB,
    "t" => $TB,
    "g" => $GB,
    "m" => $MB,
    "k" => $KB,
    "s" => $SECTOR_SIZE,
    "b" => 1,
  );
  if (defined($2)) {
    my $sizeAbbreviation = lc($2);
    if (defined($ABBREV_TO_BYTES{$sizeAbbreviation})) {
      return $1 * $ABBREV_TO_BYTES{$sizeAbbreviation};
    } else {
      croak("Unknown byte type specifier in $bytesStr: $2");
    }
  } else {
    return $1;
  }
}

######################################################################
# Find the given executable.  The search is as follows:
#   1) If program is a fully qualified path, return it immediately
#   2) Look for it in each directory of $pathRef
#   3) Look for it in $ENV{PATH} (if usePath is set)
#
# This will croak if the program is not found in the given path unless
# dontCroak is set.
#
# @param program     The name of the executable to find
# @param pathRef     The list of directories in which to search for the
#                      executable.
# @oparam usePATH    Should $ENV{PATH} be searched?  Defaults to 1.
# @oparam dontCroak  If set, return undef instead of croaking.
#                      Defaults to 0.
#
# @return A fully qualified path to the executable
# @croaks if I<DONTCROAK> is not set and the I<PROGRAM> could not be found
##
sub findExecutable {
  my ($program, $pathRef, $usePATH, $dontCroak) =
    assertMinMaxArgs([1, 0], 2, 4, @_);
  if (File::Spec->file_name_is_absolute($program)) {
    if (! -x $program) {
      if ($dontCroak) {
        return undef;
      } else {
        croak("No such executable: $program");
      }
    }
    return $program;
  }

  my @searchPath = @{$pathRef};
  if ($usePATH) {
    push(@searchPath, split(':', $ENV{PATH}));
  }

  # Try to find it within cBaseDir
  foreach my $searchDir (@searchPath) {
    my $file = makeFullPath($searchDir, $program);
    if (-x $file) {
      return $file;
    }
  }

  if ($dontCroak) {
    return undef;
  }
  croak("Couldn't find $program in (" . join(':', @searchPath) . ")");
}

######################################################################
# Find the given file in the list of directories.  The search is as follows:
#   1) If file is a fully qualified path, return it immediately
#   2) Look for it in each directory of $pathRef
#
# This will croak if the file is not found in the given path.
#
# @param file      The name of the file to find
# @param pathRef   The list of directories in which to search for the
#                  executable.
#
# @return A fully qualified path to the file
# @croaks if I<FILE> file cannot be found
##
sub findFile {
  my ($file, $pathRef) = assertMinArgs(2, @_);

  if (File::Spec->file_name_is_absolute($file)) {
    if (! -f $file) {
      croak("No such file: $file");
    }
    return $file;
  }

  my @searchPath = @{$pathRef};

  # Try to find it within each directory
  foreach my $searchDir (@searchPath) {
    my $file = makeFullPath($searchDir, $file);
    if (-f $file) {
      return $file;
    }
  }

  croak("Couldn't find $file in (" . join(':', @searchPath) . ")");
}

######################################################################
# Convert a hostname as either a hostname or a dotted quad into a
# dotted quad IP address.
#
# @param hostname              The hostname to convert
#
# @return the dotted quad IP
# @croaks if I<HOSTNAME> lookup fails
##
sub hostToIP {
  my ($hostname) = assertNumArgs(1, @_);
  my $tmp = inet_aton($hostname);
  if (!$tmp) {
    croak("cannot look up: $hostname");
  }
  return inet_ntoa($tmp);
}

######################################################################
# Check whether two IP addresses are on the same network.
#
# @param ip1         The IP address of the first host
# @param ip2         The IP address of the second host
# @param networkBits The number of network bits
#
# @return true if the addresses match up to the network bits
##
sub onSameNetwork {
  my ($ip1, $ip2, $networkBits) = assertNumArgs(3, @_);
  my $mask = (2 ** $networkBits) - 1;
  return ((unpack('I', pack('C4', split('\.', $ip1))) & $mask)
          == (unpack('I', pack('C4', split('\.', $ip2))) & $mask));
}

######################################################################
# Is the given file  in nfs?
#
# @return true if the file/dir is in nfs
##
sub inNfs {
  my ($dir) = assertNumArgs(1, @_);

  my $type = `stat -fc %T $dir`;
  chomp($type);
  return ($type eq 'nfs');
}

######################################################################
# Return a new hash containing all key-value pairs in I<HASH> where key is in
# I<KEYS>.  When any value is a hashref or listref, clone the value to produce
# a different hash or list.
#
# @param hash       A hashref containing the values to extract
# @param keys       A listref containing the keys to extract from the hash
#
# @return the extracted hash
##
sub hashExtractor {
  my ($hash, $keys) = assertNumArgs(2, @_);
  my %result;
  foreach my $key (@$keys) {
    if (exists($hash->{$key})) {
      my $value = $hash->{$key};
      if (defined($value)) {
        my $type = ref($value);
        if (($type eq 'ARRAY') || ($type eq 'HASH')) {
          $value = dclone($value);
        }
      }
      $result{$key} = $value;
    }
  }
  return %result;
}

#############################################################################
#  Serialize a hash into a unix command line argument string.
#  For key, value in the hash, generate a argument of the form --key=value.
#  Special processing for listref values converts lists into
#  comma-separated strings ( foo => [ a, b, c] ) becomes "--foo=a,b,c";
#  similar processing for hashrefs converts ( foo => { one => 1, two => 2 } )
#  to "--foo one=1,two=2".  An undef value serializes as just "--key".
#
#  @param hash    A hashref.
##
sub hashToArgs {
  my ($hash) = assertNumArgs(1, @_);
  my @args;
  foreach my $key (keys(%$hash)) {
    if (defined $hash->{$key}) {
      my $value = $hash->{$key};
      my $type = ref($value);
      if ($type eq 'ARRAY') {
        push(@args, "--$key=" . join(",", @$value));
      } elsif ($type eq 'HASH') {
        my @kv;
        foreach my $k (keys(%$value)) {
          push(@kv, "$k=$value->{$k}");
        }
        push(@args, "--$key");
        push(@args, join(",", @kv));
      } else {
        push(@args, "--$key=$value")
      }
    } else {
      push(@args, "--$key");
    }
  }
  return join(" ", @args);
}

#####################################################################
# Generate a random numerical token of fixed specified length.
#
# @param length The length of the token
#
# @return The token
##
sub makeRandomToken {
  my ($length) = assertNumDefinedArgs(1, @_);
  assertTrue($length > 0, "positive length");

  # Leading zeros confuse bash into thinking numbers are octal:
  my $ret = chr(ord('1') + int(rand 9));
  $length--;
  while ( $length > 0 ) {
    $ret .= chr(ord('0') + int(rand 10));
    $length--;
  }
  return $ret;
}

######################################################################
# Merge key-value pairs into a hashref.  If the key already exists in
# the destination hashref as a listref or a hashref, the new value
# will merged into that listref or hashref.  Scalars will simply be
# overwritten.
#
# @param hashRef  The hash ref to add the values to
# @param args     Any remaining arguments will be added as key-value pairs
#                 to the hash. May be a hash or a hashref.
#
# @return The merged hash
##
sub mergeToHash {
  my ($hashRef, @rest) = assertMinArgs(1, @_);

  # It is not possible to check that the one entry in @rest is actually a
  # hashref since ref() will return the class of a blessed hashref.
  my %args = ((scalar(@rest) == 1) ? %{$rest[0]} : @rest);
  foreach my $key (keys(%args)) {
    my $value = $args{$key};
    my $type = ref($value);
    if ($type eq 'ARRAY') {
      if (!defined($hashRef->{$key})) {
        $hashRef->{$key} = [];
      }
      if (!ref($hashRef->{$key})) {
        # Convert scalar to listref so that we can append to it
        $hashRef->{$key} = [$hashRef->{$key}];
      }
      addToList($hashRef->{$key}, 'end', @{$value});
    } elsif ($type eq 'HASH') {
      if (!defined($hashRef->{$key})) {
        $hashRef->{$key} = {};
      }
      addToHash($hashRef->{$key}, %{$value});
    } else {
      $hashRef->{$key} = $value;
    }
  }

  return $hashRef;
}

######################################################################
# Open a potentially compressed file.
#
# @param file   the file to open.
#
# @return      the filehandle if succesful, else failure
##
sub openMaybeCompressed {
  my ($file) = assertNumArgs(1, @_);

  my $sym = Symbol::gensym();
  if ($file =~ /\.gz$/) {
    if (open($sym, "gunzip -c -f $file |")) {
      return $sym;
    }
  } elsif (open($sym, "<$file")) {
    return $sym;
  } else {
    return;
  }
}

######################################################################
# Convert a ISO-8061 format date to a time in milliseconds since the
# epoch.
#
# @param date             The IS0-8061 format date string
#
# @return I<DATE>, in number of millisecons since the epoch.
# @croaks If I<DATE> is not a valid IS0-8061 format date string
##
sub parseISO8061toMillis {
  my ($date) = assertNumArgs(1, @_);
  if ($date =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2}),(\d{3})/o) {
    my ($year, $month, $day, $hh, $mm, $ss, $millis)
      = ($1, $2, $3, $4, $5, $6, $7);
    return secondsToMS(timelocal($ss, $mm, $hh, $day, ($month - 1), $year))
      + $millis;
  }
  croak("'$date' is not a valid ISO-8061 date");
}

######################################################################
# Takes one or more file names and combines them, using the correct path
# separator for the current platform. The path is cleaned up as best as
# possible (i.e. spurious .'s and //'s are removed).
#
# Note: if the resulting path is relative, then the path will always
#       begin with './'
#
# @param All args are concatenated together with the file seperator
#
# @return a concatenated path string.
##
sub makeFullPath {
  my $path = File::Spec->catfile(@_);
  if (!File::Spec->file_name_is_absolute($path)
        && (substr($path, 0, 2) ne './')) {
    return "./" . $path; # having a leading ./ is more robust.
  }
  return $path;
}

######################################################################
# Provides a way to send chat messages using sendxmpp
#
# XXX This method could use some rework. Room should be recipient and we could
# accept a flag specifying that it was sending to a conference room or not.
#
# @param room           The jabber room
# @param recipient      The jabber user to send to
# @param subject        The jabber message subject to use
# @param msg            The message to send
#
# @croaks if message cannot be sent
##
sub sendChat {
  my ($room, $recipient, $subject, $msg) = assertNumArgs(4, @_);

  if (! ($room || $recipient)) {
    croak("A room or recipient must be specified");
  }
  if ($recipient && $room) {
    croak("Cannot set a target recipient and a target room");
  }

  # At some point we may want to address the change to irc by making this
  # method utilize irc.  For the moment short-circuit the execution by
  # pretending sendxmpp doesn't exist.
  # my $sendxmpp = '/usr/bin/sendxmpp';
  my $sendxmpp = '';

  # Only try sending the message if sendxmpp exists else just return.
  if (! -e $sendxmpp) {
    return;
  }

  my ($jabberSendTo, $chatType);
  my $authUser = "testbot";
  my $pwd      = "testbot123";
  my $server   = _getImplementation()->{chat}->{server};
  my @args     = ('-t', '-r', $0);
  # File::HomeDir would be good but isn't available in our RHEL6
  # installations yet.
  my @pwdEntry = getpwnam(getUserName());
  my $conf     = $pwdEntry[7] .  "/.sendxmpprc";

  if (! -f $conf) {
    open(my $fh, ">", $conf);
    print $fh "$authUser\@$server $pwd\n";
    close($fh);
    chmod(0600, $conf);
  }

  if ($subject) {
    push(@args, '-s', $subject);
  }
  if ($room) {
    push(@args, '-c', "$room\@conference.$server");
  } else {
    push(@args, "$recipient\@$server");
  }
  # We want to force perl to use the exec() system call on sendxmpp directly
  # instead of passing the whole argument list to /bin/sh and then having
  # the shell get tripped up on metacharacters in the subject argument.
  my $pid = open(my $xmpp, "|-");
  local $SIG{PIPE} = sub { croak("whoops, $sendxmpp pipe broke") };
  if ($pid) {  # parent
    print $xmpp $msg;
    close($xmpp);
  } else {     # child
    exec($sendxmpp, @args) or exit(1);
  }
}

######################################################################
# Wait until a given condition is true, retrying at specified intervals.
# This will croak on timeout, unless the timeoutFuncRef is specified.
# Will immediately die if Ctrl+C (SIGINT) is pressed.
#
# @param condition       A code ref which should return true or false and will
#                        be repeatedly evaluated until it returns true
# @param errorMsg        Message for croak if we time out before the condition
#                        becomes true
# @oparam timeout        The number of seconds to wait on the condition
#                        (defaults to $Permabit::Constants::FOREVER).
# @oparam retryInterval  The number of seconds to wait between evaluations
#                        of condition.  0.5 will wait for half a second.
#                        And 0 will retry immediately without waiting.
#                        Defaults to 1 second.
# @oparam timeoutFuncRef A function reference to be called if the timeout
#                        is reached.
#
# @return                The return value from I<CONDITION>
##
sub retryUntilTimeout {
  my ($condition, $errorMsg, $timeout, $retryInterval, $timeoutFuncRef)
    = assertMinMaxArgs([$FOREVER, 1, \&confess], 2, 5, @_);

  # Set up signal handler for Ctrl+C
  local $SIG{INT} = sub {
    die("Interrupted by Ctrl+C\n");
  };

  my $ret;
  my $start = time();
  while (!($ret = &$condition())) {
    if ($timeout != $FOREVER) {
      my $now = time();
      if ($now > $start + $timeout) {
        my $elapsed = $now - $start;
        &{$timeoutFuncRef}("$errorMsg after " . timeToText($elapsed));
        last;
      }
    }
    if ($retryInterval > 0) {
      sleep($retryInterval);
    }
  }
  return $ret;
}

######################################################################
# Redirect STDOUT and STDERR to the given file, returning their original
# values so they can be restored with L</redirectOutput>.
#
# @param fileName             The filename to redirect to
#
# @return An array ref to a structure that can be passed to
#         restoreOutput() for restoring it.
# @croaks if stderr and stdout can't be redirected
##
sub redirectOutput {
  my ($fileName) = assertNumArgs(1, @_);
  my ($saveout, $saverr);
  open($saveout, ">&STDOUT") || croak("can't save STDOUT: $!");
  open($saverr, ">&STDERR") || croak("can't save STDERR: $!");
  open(STDOUT, "> $fileName")  || croak("can't open $fileName: $!");
  autoflush STDOUT 1;
  open(STDERR, ">&STDOUT") || croak("can't redirect STDERR: $!");
  autoflush STDERR 1;

  return [$saveout, $saverr];
}

######################################################################
# Remove one argument from a list.
#
# @param options        the initial string of options
# @param argument       argument to remove
#
# @return               the string without the excluded argument
##
sub removeArg {
  my ($options, $argument) = assertNumArgs(2, @_);
  $options =~ s/^\Q$argument\E\s*//;
  $options =~ s/\s*\Q$argument\E//;
  return $options;
}

######################################################################
# Remove all items from a list matching the given regexp and return
# them.  The list itself will no longer include those items.
#
# @param listRef        The listref that should have the items removed
# @param regexp         The regexp used to remove the items
#
# @return The list of items that matched the regexp
##
sub removeFromList {
  my ($listRef, $regexp) = assertNumArgs(2, @_);
  my @matches;
  my $i = 0;
  while ($i < scalar(@{$listRef})) {
    if ($listRef->[$i] =~ m/$regexp/) {
      push(@matches, splice(@{$listRef}, $i, 1));
    } else {
      $i++;
    }
  }
  return @matches;
}

######################################################################
# Restore STDOUT and STDERR, if they were previously redirected using
# L</redirectOutput>.
#
# @param savedOutput  The array ref returned by the previous call to
#                     redirectOutput().
#
# @croaks if stderr and stdout can't be restored
##
sub restoreOutput {
  my ($savedOutput) = assertNumArgs(1, @_);
  my ($saveout, $saverr) = @{$savedOutput};

  if ($saveout) {
    close(STDOUT);
    *TMP = *{$saveout};
    open(STDOUT, ">&TMP") || croak("can't restore STDOUT: $!");
    close(TMP);
    close(STDERR);
    *TMP = *{$saverr};
    open(STDERR, ">&TMP") || croak("can't restore STDERR: $!");
    close(TMP);
  }
}

######################################################################
# Print something to the terminal (regardless of redirections)
#
# @param message        string to print
##
sub attention {
  my ($message) = assertNumArgs(1, @_);
  if (open(my $tty, '+</dev/tty')) {
    print $tty $message;
    close($tty);
  }
}

######################################################################
# Find all test modules in a directory.  Test modules are assumed to be
# any file in the directory or its subdirectories which ends with a .pm
# extension, and which does not have a subdirectory of the same name sans
# extension (i.e. PerfTest/Pt1.pm is not a test because there is also
# a directory PerfTest/Pt1).
#
# @param path  The path from which to start looking for tests
#
# @return A list of tests as fully qualified class names
##
sub findAllTests {
  my ($path) = assertNumArgs(1, @_);
  my @tests = ();
  my %tests = ();
  my @dirs = ();

  opendir(my $d, $path);
  while (my $file = readdir($d)) {
    # Skip all dot files
    ($file =~ /^\./) && (next);

    # Skip CVS directories
    ($file eq 'CVS') && (next);

    # Build the complete path to the file
    $file = "$path/$file";

    # If it is a directory, add it to the directory list
    if (-d $file) {
      push(@dirs, $file);
      next;
    }

    # If it is a perl module, add it to the hash of tests
    ($file =~ /(.*)\.pm$/) && ($tests{$1} = 1);
  }

  # Iterate over all subdirectories removing modules whose name matches
  # a directory (i.e. a base class, not a test), and search the directory
  foreach my $dir (@dirs) {
    $tests{$dir} = 0;
    push(@tests, &findAllTests("$dir"));
  }

  # Generate the full list of tests from this directory and all of its
  # subdirectories
  foreach my $file (keys(%tests)) {
    if ($tests{$file}) {
      $file =~ s/\//::/g;
      push(@tests, $file);
    }
  }
  return @tests;
}

######################################################################
# Prompt the user on STDERR and wait until return is pressed.
#
# @oparam messages        A list of zero or more prompt messages.
#
# @return The input line
##
sub waitForInput {
  my (@messages) = @_;
  if (!@messages) {
    @messages = ("Please perform any manual operations then press return:");
  }
  my $input = *STDIN;
  my $output = *STDERR;
  my $tty;
  if (! -t STDERR and open($tty,"+</dev/tty") and -t $tty) {
    $input = *$tty;
    $output = *$tty;
  }
  print $output "\n", join("\n", @messages);
  my $line = <$input>;
  if (defined($tty)) {
    close $tty;
  }
  return $line;
}

######################################################################
# Convert a number of seconds to milliseconds.
#
# @param seconds The number of seconds to convert
#
# @return The number of seconds in milliseconds
##
sub secondsToMS {
  my ($seconds) = assertNumArgs(1, @_);
  return $seconds * 1000;
}

######################################################################
# Convert a number of minutes to milliseconds.
#
# @param minutes The number of minutes to convert
#
# @return The number of minutes in milliseconds
##
sub minutesToMS {
  my ($minutes) = assertNumArgs(1, @_);
  return secondsToMS($minutes * $MINUTE);
}

######################################################################
# Convert a number of hours to milliseconds.
#
# @param hours The number of hours to convert
#
# @return The number of hours in milliseconds
##
sub hoursToMS {
  my ($hours) = assertNumArgs(1, @_);
  return secondsToMS($hours * $HOUR);
}

######################################################################
# Execute code under a timeout
#
# @param  timeout    Number of seconds to allow the code to run.
# @param  code       Code to run.
# @oparam toolong    The message to send with when the time limit is hit.
# @oparam carpMethod The way to die if there is a timeout.
#
# @return value returned from code
##
sub timeout {
  my ($timeout, $code, $toolong, $carpMethod)
    = assertMinMaxArgs([undef, \&confess], 2, 4, @_);
  # need to capture the value of wantarray now, because inside the
  # eval it will tell us what "eval" wants.
  my $wantArray = wantarray;
  my @array;
  my $value;
  my $killTimerSig = 'TERM';
  my $timerFired = 0;
  $toolong ||= "Code took more than " . timeToText($timeout);

  # Set up an asynchronous timer to send a SIGUSR2
  my $timerSub = sub {
    my ($pid) = assertNumArgs(1, @_);
    reallySleep($timeout);
    kill("USR2", $pid);
  };
  my $timerTask = Permabit::AsyncSub->new(code => $timerSub,
                                          args => [$PID],
                                          expectedSignals => [$killTimerSig]);
  # Run the code under a SIGUSR2 handler
  local $SIG{USR2} = "IGNORE";
  eval {
    local $SIG{USR2} = sub {
      $timerFired = 1;
      die($toolong);
    };
    {
      local $SIG{$killTimerSig} = 'DEFAULT';
      $timerTask->start();
    }
    if ($wantArray) {
      @array = $code->();
    } else {
      $value = $code->();
    }
  };
  my $err = $EVAL_ERROR;
  $timerTask->kill($killTimerSig);
  $timerTask->wait();
  if ($timerFired) {
    no strict 'refs';
    &{$carpMethod}($toolong);
  } elsif ($err) {
    &{$carpMethod}("code threw: '" . $err . "'");
  } elsif ($wantArray) {
    return @array;
  } else {
    return $value;
  }
}

######################################################################
# Returns the given value rounded up to the nearest multiple.  For example,
# <tt>ceilMultiple(1.4, 1)</tt> is equivalent to <tt>ceil(1.4)</tt>, and
# returns <tt>2</tt>; <tt>ceilMultiple(59, 16)</tt> returns <tt>64</tt>.
#
# @param value       The value to ceiling
# @param multiple    The multiple (a positive integer) to ceiling to
#
# @return            the given value rounded up to the nearest multiple
##
sub ceilMultiple {
  my ($value, $multiple) = assertNumArgs(2, @_);

  assertRegexpMatches(qr/^\d+\z/, $multiple,
                      "multiple argument must be an integer");
  assertLTNumeric(0, $multiple,
                  "multiple argument must be a positive integer");

  if ($value =~ /^-?\d+\z/) {
    # Looks like an integer.
    # Converting to float to use ceil() may lose precision.

    $value = $value + 0;

    use integer;
    # This rounds towards zero. But we want to round towards positive
    # infinity. If $value is negative, those are the same direction;
    # if it's positive, we may need to make a correction.
    my $quotient = $value / $multiple;
    if (($value > 0) && ($value % $multiple) != 0) {
      $quotient++;
    }
    return $quotient * $multiple;
  } else {
    # Assume anything else is a float.
    return $multiple * ceil($value/$multiple);
  }
}

######################################################################
# Convert a number of seconds to a human-readable format.
#
# For times smaller than a minute, the time will be reported as a number
# plus the word "seconds".  For larger times, the format will be
# "minutes:seconds".
#
# When the time is an integer, the time will be an integer.  For example,
# "57 seconds" or "10:06".  When the time is not an integer, 3 digits of
# fraction will be reported.  For example, "32.768 seconds" or "10:48.576".
#
# @param  seconds  The number of seconds
#
# @return A human-readable string for that number of seconds.
##
sub timeToText {
  my ($seconds) = assertNumArgs(1, @_);
  my $minutes = int($seconds / 60);
  $seconds -= 60 * $minutes;
  my $s = sprintf((int($seconds) == $seconds)
                  ? ($minutes ? "%02d" : "%d")
                  : ($minutes ? "%06.3f" : "%.3f"),
                  $seconds);
  my $hours = int($minutes / 60);
  $minutes -= 60 * $hours;
  if ($hours) {
    return "$hours:" . sprintf("%02d", $minutes) . ":$s";
  } elsif ($minutes) {
    return "$minutes:$s";
  } elsif ($seconds && ($seconds < (10 * $MICROSECOND))) {
    return sprintf("%.3f", $seconds / $MICROSECOND) . " microseconds";
  } elsif ($seconds && ($seconds < (10 * $MILLISECOND))) {
    return sprintf("%.3f", $seconds / $MILLISECOND) . " milliseconds";
  } else {
    return "$s seconds";
  }
}

######################################################################
# Parses a YAML file and returns a hash ref containing its data
#
# @param yamlFile     the path to yaml file
#
# @return A hash ref containing the YAML data
# @croaks If I<YAMLFILE> doesn't exist or is not readable
##
sub getYamlHash {
  my ($yamlFile) = assertNumArgs(1, @_);
  if (! -e $yamlFile) {
    croak("$yamlFile does not exist");
  } elsif (! -r $yamlFile) {
    croak(getUserName() . " does not have read permission for $yamlFile");
  } else {
    return YAML::LoadFile($yamlFile);
  }
}

######################################################################
# Return a YAML hash given a string of YAML data
#
# @param data  The YAML data
#
# @return      The YAML hash
##
sub yamlStringToHash {
  my ($data) = assertNumArgs(1, @_);
  assertDefined($data, "no output to parse");
  return YAML::Load($data);
}

######################################################################
# Sleep a specified number of seconds, even when interrupted.  This
# method tries to be as reliable as possible but it's not real-time-OS
# sleeping.
#
# @param sleepSeconds   The amount of time to really sleep in seconds
##
sub reallySleep {
  my ($sleepSeconds) = assertNumArgs(1, @_);
  my $usecs = 1000000 * $sleepSeconds;
  do {
    $usecs -= usleep($usecs);
  } while ($usecs > 0);
}

#############################################################################
# If an exception is of the named type, rethrow it.
#
# @param error  The error or exception, normally from $EVAL_ERROR.
# @param type   The type.
#
# @croaks if the error is an object of that type.
##
sub rethrowException {
  my ($error, $type) = assertNumArgs(2, @_);
  if (ref($error) && $error->isa($type)) {
    die($error);
  }
}

#############################################################################
# Apply a supplied code block or subroutine to a list of arguments,
# concurrently, and return an array of results. If any of the
# evaluations dies, we still wait for the remainder to complete before
# re-raising the error. (In the case of multiple failures, the error
# we return will be the one corresponding to the first value in the
# list for which evaluation fails, not necessarily the subprocess that
# returns an error first.)
#
# Thanks to the prototype, this can be used with code blocks similar
# to "map" or "grep" if desired:
#
#   mapConcurrent { $_->runSomeMethod() } @things;
#
# N.B.: Currently only scalar results per application are handled, so
# uses similar to "map" like:
#
#   mapConcurrent { $_ => foo($_) } @stuff
#
# don't work (yet).
#
# @param code  A code block or subroutine to apply to "$_"
# @param rest  The values to apply the code block to
#
# @return  An array of results
##
sub mapConcurrent(&@) { ## no critic (ProhibitSubroutinePrototypes)
  my ($code, @args) = assertMinArgs(1, @_);
  # A top-level "use" results in circular dependencies during load. If
  # the caller hasn't already loaded Permabit::Async, we won't find
  # its "new" method without loading it now.
  eval { require Permabit::Async; };
  my @tasks;
  # This must be $_ for the code block to work the way we want.
  for $_ (@args) {
    my $sub = sub { $code->($_); };
    my $task = Permabit::AsyncSub->new(code => $sub);
    $task->start();
    push(@tasks, $task);
  }
  my @results;
  my $error;
  for my $task (@tasks) {
    my $result;
    eval {
      $result = $task->result();
    };
    if ($EVAL_ERROR) {
      $error //= $EVAL_ERROR;
    } else {
      push(@results, $result);
    }
  }
  if ($error) {
    confess($error);
  }
  return @results;
}

1;
