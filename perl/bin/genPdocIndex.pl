#!/usr/bin/perl

##
# This script generates an index file for all of the generated pdoc
# html in the given directory.
#
# @synopsis
#
# genPdocIndex.pl <DIR>
#
# $Id$
##
use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use File::Find;

my $HTML_BASE = "http://127.0.0.1/~$ENV{USER}/perldoc";

# Map from package name to arrayref of the modules in that package
my %modules;

# Map from package name to the directory that package lives in
my %dir;

# The base directory to find html files in
my $baseDir;

main();

######################################################################
# Print the HTML header for the index file, including a summary of all
# packages.
##
sub printHeader {
  my $header = <<HEADER;
<html>
<head>
  <title>Documentation for Permabit perl modules</title>
</head>
<body bgcolor = "white">

<h1>Documentation for Permabit perl modules</h1>
HEADER
  print INDEX $header;

  # Now print a summary with links to the various packages
  print INDEX "<ul>\n";
  foreach my $package (sort keys %modules) {
    print INDEX "<li><a href=\"#$package\">$package Modules</a></li>\n";
  }
  print INDEX "</ul><hr><br>\n";
}

######################################################################
# Print the HTML trailer.
##
sub printTrailer {
  print INDEX "\n<br><hr>\nAuto-Generated on " . localtime() . "\n";
  print INDEX "</body></html>\n";
}

######################################################################
# Print a section header for the given package.
#
# @param package    The package to print the header for
##
sub printPackageHeader {
  my ($package) = @_;
  print INDEX "\n<h1><a name=\"$package\">$package Modules</a></h1>\n";
}

######################################################################
# Print the link for the given module in the given package
#
# @param package        The package the module lives in
# @param module         The name of the module
##
sub printHref {
  my ($package, $module) = @_;
  my $dir = $dir{$package};
  if ($package =~ m/^[a-z]/) {
    $package = "";
  } else {
    $package .= "::";
  }
  print INDEX
    "<a href=\"$HTML_BASE/${dir}/${module}\">${package}${module}</a><br>\n";
}

######################################################################
# Method invoked by File::Find on each file.  This builds up the
# %modules and %dirs hashes.
##
sub wanted {
  if (/\.html$/) {
    my $dir = ${File::Find::dir};
    if ($dir eq $baseDir) {
      # Ignore files at the top level
      return;
    }
    # Strip off leading $baseDir
    $dir =~ s|^$baseDir/||;
    my $package = $dir;
    $package =~ s|^([a-z]\w+/)||;
    $package =~ s|/|::|g;
    if (exists $dir{$package}) {
      # We already have a package with this name, so our shortening
      # was incorrect.  Leave it as it was.
      $package = $dir;
    }
    $dir{$package} = $dir;
    push(@{$modules{$package}}, $_);
  }
}

######################################################################
##
sub main {
  $baseDir = $ARGV[0] || '.';
  $baseDir =~ s|/$||;
  my $index = "$baseDir/index.html";
  open(INDEX, "> $index") || die("Couldn't open $index");
  find(\&wanted, $baseDir);
  printHeader();
  foreach my $package (sort keys %modules) {
    printPackageHeader($package);
    foreach my $module (sort @{$modules{$package}}) {
      printHref($package, $module);
    }
  }
  printTrailer();
  close(INDEX) || die("Couldn't close $index");
}
