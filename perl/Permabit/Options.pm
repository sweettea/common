##
# Set complex config options from the command line
#
# $Id$
#
# @synopsis
#
# Set complex configuration options from the command line
#
# Argument names are specified as --<arg> and wil have value 1
# Arguments with scalar values are specified as
#   --<arg>=<value>
# Arguments with array values are specified as
#   --<arg>=<value1>,<value2>...
# Arguments with hash values are specified as:
#   --<arg>=<key1>=<value1>,<key2>=<value2>
#
# '=' may be represented as \=
# ',' may be represented as \,
#
# @bugs
#
# This needs better pod.
##
package Permabit::Options;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use base qw(Exporter);
use Text::ParseWords qw(parse_line);

our @EXPORT_OK = qw(parseARGV
                    parseArray
                    parseOptionsString);

######################################################################
# Parse arguments in @at@ARGV (which will have all parsed arguments removed),
#
# @param defaults  An optional hash of default arguments
#
# @return A hashref of parsed options
##
sub parseARGV {
  my $hash;
  ($hash, @ARGV) = parseArray([@ARGV], @_);
  return $hash;
}

######################################################################
# Tokenize a string into an array of options and then parse them.
# Arguments are delimited by spaces.  Arguments with spaces may be
# quoted with either single or double quotes.
#
# @param optionString The options to parse
#
# @return A list the first element of which is a hashref of parsed options and
#         the remaining elements holding any unparsed arguments
##
sub parseOptionsString {
  # deal with options when we don't have the shell's tokenizer available

  # limitations:
  #   requires quotes in an argument value to quote the entire value
  my @tokens
    = map { $_ = _stripQuotes($_); } parse_line(" ", 1, shift(@_));
  return parseArray([@tokens], @_);
}

######################################################################
# Helper function to remove quotes.
##
sub _stripQuotes {
  my ($token) = @_;
  $token =~ s/^\'(.*)\'$/$1/;
  $token =~ s/^\"(.*)\"$/$1/;
  return $token;
}

######################################################################
# Helper function to convert special characters
##
sub _quoteSpecial {
  my ($text) = @_;

  # Replace escaped equals signs with \001
  $text =~ s/\\=/\001/g;

  # Replace escaped commas with \002
  $text =~ s/\\,/\002/g;

  return $text;
}

######################################################################
# Helper function undo special character conversion
##
sub _unquoteSpecial {
  my ($text) = @_;

  $text =~ s|\001|=|g;
  $text =~ s|\002|,|g;

  return $text;
}

######################################################################
# Parse an arrayref of arguments into a hash.
#
# @param args      The arrayref of args to parse
# @param defaults  An optional hash of default arguments
#
# @return A list the first element of which is a hashref of parsed options and
#         the remaining elements holding any unparsed arguments
##
sub parseArray {
  my $args = shift(@_);
  my @args = @{$args};
  my %args = @_;
  my @remaining = ();
  while (@args) {
    my $arg = shift(@args);

    # Everything following '--' should not be parsed
    ($arg eq '--') && (push(@remaining, @args), last);

    if ($arg =~ /^--(.*)$/) {
      my $key = $1;
      $key = _stripQuotes($key);
      my $value = 1;

      $key = _quoteSpecial($key);

      if ($key =~ /(.*?)=(.*)/) {
        $key = $1;
        $value = $2;
      }

      $value = _stripQuotes($value);

      if ($value =~ /=/) {
        my %kvpairs = ();
        foreach my $pair (split(',', $value)) {
          # Convert escaped = back to = while expanding into a hash
          if ($pair =~ /=/) {
            my @pair = map { _unquoteSpecial($_) } split('=', $pair);
            $kvpairs{$pair[0]} = $pair[1] // '';
          } else {
            $kvpairs{_unquoteSpecial($pair)} = 1;
          }
        }
        $value = {%kvpairs};
      } elsif ($value =~ /,/) {
        my @values = map { _unquoteSpecial($_); } split(',', $value);
        $value = [@values];
      } else {
        # Convert escaped = back to =
        $value = _unquoteSpecial($value);
      }

      $key = _unquoteSpecial($key);
      $args{$key} = $value;
    } else {
      push(@remaining, $arg);
    }
  }

  return {%args}, @remaining;
}

1;
