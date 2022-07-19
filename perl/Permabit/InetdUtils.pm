##
# Utilities for configuring inetd and xinetd.
#
# $Id$
##
package Permabit::InetdUtils;

use strict;
use warnings FATAL => qw(all);
use Carp;
use English qw(-no_match_vars);
use File::Basename;
use Log::Log4perl;
use Permabit::Assertions qw(assertMinMaxArgs assertNumArgs);
use Permabit::Constants;
use Permabit::PlatformUtils qw(isDebian isRedHat isSles isUbuntu);
use Permabit::SystemUtils qw(assertCommand createRemoteFile runSystemCommand);
use base qw(Exporter);

our @EXPORT_OK = qw (getRemoveServiceCmd isServiceConfigured);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

#############################################################################
# Returns string containing system command to remove a service from the 
# inetd.conf file for the Debian platform.
#
# @param args settings for the service to be removed
#
# @return string containing system command
#
# Directing update-inetd into /dev/null works around a limitation which
# prevents update-inetd from working correctly without a controlling terminal.
##
sub _getRemoveServiceDebianCmd {
  my ($port) = assertNumArgs(1, @_);

  return "sudo update-inetd --remove $port > /dev/null";
}


#############################################################################
# Returns string containing system command to remove a service from xinetd
# if it is found there.  For Redhat or Suse platform.
#
# @param name of the service to remove
# @param optional flag indicating that xinetd should be restarted
#
# @return string containing system command
##
sub _getRemoveServiceRedhatOrSuseCmd {
  my ($serviceName, $restartFlag) = assertMinMaxArgs([1], 1, 2, @_);

  my $cmd = "sudo rm -f /etc/xinetd.d/" . $serviceName;
  if ($restartFlag) {
    $cmd = $cmd . " && sudo service xinetd --full-restart";
  }
  return $cmd;
}

#############################################################################
# Returns string containing system command to remove a service from (x)inetd 
# for Debian, Redhat, or Suse platform.
#
# @param service_name is the name of the service to remove
# @param port the port that the service communicates on
#
# @return string containing system command
##
sub getRemoveServiceCmd {
  my ($serviceName, $port) = assertNumArgs(2, @_);
  if (isDebian() || isUbuntu()) {
    return _getRemoveServiceDebianCmd($port);
  }
  if (isRedHat() || isSles()) {
    return _getRemoveServiceRedhatOrSuseCmd($serviceName);
  }
  croak("unrecognized platform.");
}

#############################################################################
# Check whether a service is configured in (x)inetd for Debian, Redhat, or 
# Suse platform.
#
# @param service_name is the name of the service to remove
#
# @return 1 if service is configured and zero otherwise.
##
sub isServiceConfigured {
  my ($serviceName) = assertNumArgs(1, @_);
  my $isConfigured = 0;

  if (isDebian() || isUbuntu()) {
    # Scan for service name in inetd configuration file.
    my $cmd = "cat /etc/inetd.conf";
    my $result = runSystemCommand($cmd);
    if ( $result->{returnValue} != 0) {
      confess("Error reading inetd configuration file:\n" 
              . $result->{stderr});
    }

    if ($result->{stdout} =~ /$serviceName/) {
      $isConfigured = 1;
    }
  }
  elsif (isRedHat() || isSles()) {
    # Check for service name subdirectory under xinetd.d configuration
    # directory.
    if (-e "/etc/xinetd.d/" . $serviceName) {
      $isConfigured = 1;
    }
  }
  else {
    croak("unrecognized platform.");
  }

  return $isConfigured;
}

