##
# Log4perl utility functions.
#
# @synopsis
#
#     use Permabit::Log4perlUtils qw(progressDot progressFinished);
#
#     for my $i (1..20) {
#       # Do stuff
#       progressDot($log);
#     }
#     progressFinished($log);
#
# @description
#
# C<Permabit::Log4perlUtils> provides utility methods for interacting
# with Log4perl to provide missing functionality.  It provides a
# functional interface to these methods due to their static nature.
#
# $Id$
##
package Permabit::Log4perlUtils;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Carp qw(croak);
use Permabit::Assertions qw(assertNumArgs);

use base qw(Exporter);

our @EXPORT_OK = qw (
  progressDot
  progressFinished
);

our $VERSION = 1.0;

# Map from logger categories to the appender each is using.
my %APPENDERS;

# The layout used when printing progress dots
my $PROGRESS_LAYOUT = Log::Log4perl::Layout::PatternLayout->new("%m");

##########################################################################
# Log a progress dot.
#
# @param log            The logger to use
##
sub progressDot {
  my ($log) = assertNumArgs(1, @_);
  _progress($log, '.');
}

##########################################################################
# Log that a sequence of progress dots has completed.
#
# @param log            The logger to use
##
sub progressFinished {
  my ($log) = assertNumArgs(1, @_);
  _progress($log, "\n");
}

######################################################################
# Return the first Log::Log4perl::Appender found for the given Logger.
# To be completely correct, this should probably return all appenders
# found, recursing until a Logger without additivity is reached.  But
# this should be sufficient for now.
#
# @param log    The logger to find the Appender for
#
# @return The first Log::Log4perl::Appender found.
#
# @croaks If no appenders are found
##
sub _findFirstAppender {
  my ($log) = assertNumArgs(1, @_);
  # Turn off warning about APPENDER_BY_NAME only being used once
  no warnings qw(once);
  for (my $logger = $log; $logger; $logger = $logger->parent_logger()) {
    foreach my $appender_name (@{$logger->{appender_names}}) {
      return $Log::Log4perl::Logger::APPENDER_BY_NAME{$appender_name};
    }
  }
  croak("No Appenders found for Logger $log->{category}");
}

######################################################################
# Log progress text.
#
# @param log    The logger to use
# @param text   The text to log
##
sub _progress {
  my ($log, $text) = assertNumArgs(2, @_);

  if (!$log->is_debug()) {
    return;
  }

  $APPENDERS{$log->{category}} ||= _findFirstAppender($log);
  my $appender = $APPENDERS{$log->{category}};
  my $defaultLayout = $appender->layout();
  $appender->layout($PROGRESS_LAYOUT);
  $log->debug($text);
  $appender->layout($defaultLayout);
}

1;
