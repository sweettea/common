#!/bin/sh
#
# Report on the network state of a host (used by
# Permabit::SystemUtils::getHostNetworkState()).
#
# $Id$

WATCHDOG_MSGS='NETDEV WATCHDOG:.*transmit timed out'
E1000_DRIVER='Intel(R) PRO/1000 Network Driver'

PATH=$PATH:/sbin:/usr/sbin
uname -a
uptime
ifconfig -a
netstat -rn
arp -na

# Find out if the e1000 driver is on this machine
dmesg | grep -F "$E1000_DRIVER"

if test -f /var/log/boot -o -f /var/log/boot.gz ; then
  # Debian
  sudo zgrep "$E1000_DRIVER" /var/log/boot;
else
  # SLES
  sudo grep "$E1000_DRIVER" /var/log/boot.msg;
fi

lspci | grep Ethernet

# Look for the watchdog errors in messages and syslog
if test -f /var/log/syslog; then
  maybeSyslog=/var/log/syslog;
else
  maybeSyslog=;
fi
  
sudo grep "$WATCHDOG_MSGS" /var/log/messages $maybeSyslog | grep -v sudo
