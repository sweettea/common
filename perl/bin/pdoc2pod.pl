#!/usr/bin/perl

##
# Convert Permabit style perl documentation (pdoc) to pod
#
# @synopsis
#
#     pdoc2pod.pl FILE [FILE...]
#
# @description
#
# See L<Pdoc::Generator> for perldoc syntax.
#
# $Id$
##

use FindBin;
use lib "${FindBin::RealBin}/../lib";

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use File::Spec;
use Getopt::Long;
use Log::Log4perl qw(:easy);
use Pdoc::Generator qw(pdoc2help pdoc2usage);

# Initialize log4perl
Log::Log4perl->easy_init({layout => '%m%n',
                          level  => $WARN,
                          file   => "STDOUT"});

######################################################################
# Generate pod for all files listed on the command line.
##
sub main {
  my $script = File::Spec->catfile($FindBin::RealBin, $FindBin::RealScript);
  GetOptions("help" => sub { pdoc2help($script) }) or pdoc2usage($script);;
  if (!@ARGV) {
    pdoc2usage($script);
  }
  foreach my $file (@ARGV) {
    if (! -f $file) {
      die("$file doesn't exist\n");
    }
    my $generator
      = Pdoc::Generator->new(filename => File::Spec->rel2abs($file));
    my $output .= join('', $generator->generatePod());
    $output =~ s/\n\n\n+/\n\n/sg;
    print $output;
  }
}

main();

1;
