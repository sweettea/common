##
# Provides many methods, both object oriented and not, to manage class
# level global parameters.
#
# $Id$
#
# @synopsis
#
#     use Permabit::Parameterizer;
#     my $params = Permabit::Parameterizer->new(__PACKAGE__);
#
#     $params->setParameter('foo', 1);
#     return $params->getParameter('foo');
#
#     $params->bar(1);
#     return $params->bar();
#
# @description
#
# C<Permabit::Parameterizer> maintains a hash of parameters for each
# parameter domain (usually a class).  It provides non-object oriented
# get and set methods which can be used to manipulate the parameters
# for any given domain. It also provides a getParameterList() method
# to retrieve the names of all defined parameters in a domain, and a
# getParameters() method to retrieve the entire has for a domain.
#
# A C<Permabit::Parameterizer> object may be instantiated for a given
# parameter domain.  This object provides all of the same methods as
# the non-object oriented versions.  In addition, the object provides
# a method for each parameter which may be used to get or set that
# parameter.  In other words, a parameter object for a given domain
# may manipulate parmeter foo either by calling $object->get('foo') and
# $object->set('foo', value), or by calling $object->foo() and
# $object->(value).
##
package Permabit::Parameterizer;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

# Hash of all packages and their parameters
my %params = ();

#############################################################################
# Instantiate a new parameter domain object
#
# @param domain  The name of the parameter domain
##
sub new {
  my ($pkg, $domain) = @_;
  return bless { domain => $domain }, $pkg;
}

#############################################################################
# Set the value of a parameter.
#
# @param dom   The domain for this parameter (omit if calling via OO).
# @param param The name of the parameter
# @param value The value to which to set the parameter
#
# @return The previous value of the parameter.
##
sub setParameter {
  my ($dom, $param, $value) = @_;
  $dom = &_getDomain($dom);
  my $oldValue = $params{$dom}{$param};
  $params{$dom}{$param} = $value;
  return $oldValue;
}

#############################################################################
# Get the value of a parameter
#
# @param dom   The domain for this parameter (omit if calling via OO).
# @param param The name of the parameter
##
sub getParameter {
  my ($dom, $param) = @_;
  $dom = &_getDomain($dom);
  return $params{$dom}{$param};
}

#############################################################################
# Get the list of all parameters for a given domain
#
# @param dom   The domain for this parameter (omit if calling via OO).
##
sub getParameterList {
  my $dom = shift(@_);
  $dom = &_getDomain($dom);
  return keys(%{$params{$dom}});
}

#############################################################################
# Get the hash of all parameters and their values for a given domain
#
# @param dom   The domain for this parameter (omit if calling via OO).
##
sub getParameters {
  my $dom = shift(@_);
  $dom = &_getDomain($dom);
  return $params{$dom};
}

#############################################################################
# AUTOLOAD provides a get/set function for each parameter called as the
# parameter's name.
##
sub AUTOLOAD {
  no strict 'refs';
  our $AUTOLOAD;
  my $param = $AUTOLOAD;
  $param =~ s/.*:://;
  *$AUTOLOAD = sub { _setOrGet($param, @_); };
  goto &$AUTOLOAD;
}

#############################################################################
##
sub _getDomain {
  return (ref($_[0])) ? $_[0]->{domain} : $_[0];
}

#############################################################################
##
sub _setOrGet {
  my ($param, $self, $value) = @_;
  my $domain = &_getDomain($self);
  (defined($value)) && (return &setParameter($domain, $param, $value));
  return &getParameter($domain, $param);
}

1;
