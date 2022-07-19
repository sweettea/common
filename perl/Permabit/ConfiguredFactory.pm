##
# Instantiate and configure objects based on a configuration file.
#
# @synopsis
#
#     use Permabit::ConfiguredFactory;
#
#     $foobar = Permabit::ConfiguredFactory::make('Foo::Bar');
#
# @description
#
# C<Permabit::ConfiguredFactory> provides a mechanism to instantiate
# and configure objects based on a YAML configuration file. See
# ConfiguredFactory.yaml in the same directory as this module for a
# description of the configuration parameters and to see the defaults.
#
# It is intended to be used via inheritance from
# C<Permabit::Configured> rather than directly.
#
# $Id$
##
package Permabit::ConfiguredFactory;

use strict;
use warnings FATAL => qw(all);
use Carp qw(croak);
use English qw(-no_match_vars);
use Log::Log4perl;

use Class::Inspector;
use File::Spec;
use Storable qw(dclone);
use YAML;

use Permabit::Assertions qw(
  assertMinArgs
  assertMinMaxArgs
  assertNumArgs
);
use Permabit::Utils qw(getYamlHash);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my $CONFIG;
my $SYSTEM_CONFIGURATION = "/etc/permabit/perl.yaml";
my %DISABLED = ();

########################################################################
# Instantiate a new object of the specified type.
#
# @param  class       The class of the object to be instantiated
# @oparam parameters  An optional hash of additional parameters to the new
#                     object, any parameters specified here will override those
#                     in the config
#
# @return The requested object
##
sub make {
  my ($class, %parameters) = assertMinArgs(1, @_);
  loadConfiguration();

  if (!exists($CONFIG->{$class})) {
    croak("Can't instantiate a $class, it is misconfigured.");
  }

  my $classConfig = $CONFIG->{$class};
  my $status = $classConfig->{status} // '';
  my $config = $classConfig->{config} // {};

  if ($status ne 'disabled') {
    if (exists($classConfig->{class})) {
      return _replaceClass($classConfig->{class},
                           $classConfig->{file},
                           $config,
                           %parameters);
    }

    if ($status eq '') {
      $status = ((scalar(keys(%{$config})) == 0) ? 'disabled' : 'enabled');
    } elsif ($status ne 'enabled') {
      croak("Invalid status: $status for $class");
    }
  }

  if ($status eq 'disabled') {
    disable($class);
  }

  my $object = bless { %{$config}, %parameters }, $class;
  $object->initialize();
  return $object;
}

########################################################################
# Replace a class with the one specified in the config file.
#
# @param class        The replacement class
# @param file         If defined, the file from which to load the replacement
#                     class
# @param config       The configuration dictionary from the class being
#                     replaced
# @oparam parameters  An optional hash of additional parameters to the new
#                     object, any parameters specified here will override those
#                     in the config
#
# @return The replacement object
##
sub _replaceClass {
  my ($class, $file, $config, %parameters) = assertMinArgs(3, @_);
  if (defined($file)) {
    $log->info("require $file; import $class");
    eval("require '$file'; import $class");
    if ($EVAL_ERROR) {
      die($EVAL_ERROR);
    }
  } else {
    eval("use $class");
  }

  return $class->new(%{$config}, %parameters);
}

########################################################################
# Determine the path of the config file to load.
#
# * The location specified in the PERMABIT_PERL_CONFIG environment variable
# * $Permabit::Configuration::SYSTEM_CONFIGURATION if the specified file
#   exists
# * ConfiguredFactory.yaml in the directory containing this module
#
# @return  a pathname
#
# @croaks  if $PERMABIT_PERL_CONFIG is unset and the standard config
#          file locations do not exist
##
sub _findConfigPath {
  my $configFile = $ENV{PERMABIT_PERL_CONFIG};
  if (!defined($configFile)) {
    if (-r $SYSTEM_CONFIGURATION) {
      $configFile = $SYSTEM_CONFIGURATION;
    } else {
      $configFile =  Class::Inspector->loaded_filename(__PACKAGE__);
      $configFile =~ s/pm$/yaml/;
      $log->info("no $SYSTEM_CONFIGURATION, looking for $configFile");
      if (! -r $configFile) {
        croak("unable to find $SYSTEM_CONFIGURATION or $configFile");
      }
    }
  }
  return $configFile;
}

########################################################################
# Initialize the configuration. This method will automatically be called from
# make().
#
# @croaks if no config file is found
##
sub loadConfiguration {
  if (defined($CONFIG)) {
    return;
  }

  $CONFIG = _loadConfigFile(_findConfigPath());
  my $testcaseOverride = $ENV{PERMABIT_PERL_TESTCASE_CONFIG_OVERRIDE};
  if (defined($testcaseOverride)) {
    $CONFIG = _mergeConfigs(_loadConfigFile($testcaseOverride), $CONFIG);
  }
}

########################################################################
# Load a configuration file and recursively merge it with any included
# configurations. This function should only be called from loadConfiguration().
#
# @param configFile  The file to load
#
# @return The fully merged config
#
# @croaks if the configFile or any of its includes can not be loaded
##
sub _loadConfigFile {
  my ($configFile) = assertNumArgs(1, @_);
  $log->debug("loading $configFile");
  my $config = getYamlHash($configFile);
  my $include = delete($config->{include});
  if ($include) {
    if (!File::Spec->file_name_is_absolute($include)) {
      # If the include is relative, take it relative to the directory of the
      # file doing the including.
      my @pathComponents = File::Spec->splitpath($configFile);
      $include = File::Spec->catfile($pathComponents[1], $include);
    }

    return _mergeConfigs(_loadConfigFile($include), $config);
  }

  return $config;
}

######################################################################
# Modify a config based on another config. Examines each key of the
# modifier config. If a key starts with a '+', the value of that key
# (sans +) will replace any value in the original config, or will be
# added if it does not exist in the original config. If a key starts
# with a '-', that key (sans -) and everything under it will be
# removed from the original config. If a key starts with any other
# symbol, it will be added to the original config if the original
# config does not already contain it. Otherwise, the values below that
# key will be merged recursively if they are a hash, and croak if they are
# a scalar.
#
# @param  config     The config to be modified
# @param  modifier   The modifications to the original config
# @oparam keyPath    Where in the config we are currently working
#
# @return The modified hash
##
sub _mergeConfigs {
  my ($config, $modifier, $keyPath) = assertMinMaxArgs([''], 2, 3, @_);
  my $type = ref($modifier);
  if ($type ne 'HASH') {
    if ((ref($config) ne 'HASH') || (scalar(keys(%{$config})) == 0)) {
      return $modifier;
    } else {
      croak("Can't replace hash with scalar at $keyPath");
    }
  }

  if (ref($config) ne 'HASH') {
    return _mergeConfigs({}, $modifier, $keyPath);
  }

  foreach my $key (keys(%{$modifier})) {
    my $newKeyPath = "${keyPath}/$key";
    if ($key =~ /^\+(.*)$/) {
      $config->{$1} = $modifier->{$key};
      next;
    }

    if ($key =~ /^\-(.*)/) {
      delete $config->{$1};
      next;
    }

    $config->{$key} = _mergeConfigs($config->{$key} // {},
                                    $modifier->{$key},
                                    $newKeyPath);
  }

  return ((scalar(keys(%{$config}))) == 0) ? undef : $config;
}

########################################################################
# Disable a class by replacing (almost) all of its methods with no-ops.
#
# @param class  The class to disable
##
sub disable {
  my ($class) = assertNumArgs(1, @_);
  if ($DISABLED{$class}) {
    return;
  }

  $log->debug("Disabling $class");
  foreach my $method (@{Class::Inspector->methods($class)}) {
    if ($method eq 'new') {
      next;
    }

    my $fullMethodName = join('::', $class, $method);
    eval {
      no warnings 'redefine';
      no strict 'refs';
      *{$fullMethodName} = sub { return wantarray ? () : undef };
    }
  }

  $DISABLED{$class} = 1;
}

########################################################################
# Get a copy of the loaded configuration.
#
# @return A copy of the configuration
##
sub getConfiguration {
  loadConfiguration();
  return dclone($CONFIG);
}

########################################################################
# Discard any loaded config file data so we can start afresh. Intended
# for testing only.
##
sub reset {
  $CONFIG = undef;
}

1;
