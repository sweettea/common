##
# This module represents the pdoc2pod context when parsing a
# file.
#
# $Id$
##
package Pdoc::File;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Permabit::Assertions qw(assertNumArgs);
use Storable qw(dclone);

####################################################################
# Default author for files, if no other is specified
##
my $DEFAULT_AUTHOR
  = "Red Hat VDO Team E<lt>F<vdo-devel\@redhat.com>E<gt>";

##
# @paramList{new}
my %properties
  = (
     # @ple The author of this file
     author                     => undef,
     # @ple Any bugs in this implementation
     bugs                       => undef,
     # @ple A textual description of what this file does
     description                => undef,
     # @ple The Pdoc::Functions in this file
     functions                  => [],
     # @ple The name of this file
     name                       => undef,
     # @ple A summary of this file
     summary                    => undef,
     # @ple A synopsis of how this file is used
     synopsis                   => undef,
     # @ple The version of this file
     version                    => undef,
    );
##

######################################################################
# Constructor
#
# @params{new}
##
sub new {
  my $invocant = shift(@_);
  my $class = ref($invocant) || $invocant;
  my $self = bless {%{ dclone(\%properties) },
                    # Overrides previous values
                    @_
                   }, $class;
  $self->{author} ||= $DEFAULT_AUTHOR;
  $self->{_currLevel} = 0;
  $self->{_currSection} = \$self->{summary};
  return $self;
}

######################################################################
# Append to the bugs section to this file
#
# @param bugs   Text to add to the bugs section
##
sub addBugs {
  my ($self, $bugs) = assertNumArgs(2, @_);
  $self->{bugs} .= $bugs;
  $self->{_currSection} = \$self->{bugs};
}

######################################################################
# Append to the textual description of this file.
#
# @param description   Text to add to the description section
##
sub addDescription {
  my ($self, $description) = assertNumArgs(2, @_);
  $self->{description} .= $description;
  $self->{_currSection} = \$self->{description};
}

######################################################################
# Add an item tag to the current section
#
# @param item   The name of the item tag
# @param text   Textual description of that item tag
##
sub addItem {
  my ($self, $item, $text) = assertNumArgs(3, @_);
  ${$self->{_currSection}} .= "=item I<$item>: $text\n\n";
}

######################################################################
# Add a function to this file
#
# @param function   Pdoc::Function to add to the function list
##
sub addFunction {
  my ($self, $function) = assertNumArgs(2, @_);
  push(@{$self->{functions}}, $function);
}

######################################################################
# Append to the summary of this file.
#
# @param summary   Text to add to the summary section
##
sub addSummary {
  my ($self, $summary) = assertNumArgs(2, @_);
  $self->{summary} .= $summary;
  $self->{_currSection} = \$self->{summary};
}

######################################################################
# Append to the synopsis of this file.
#
# @param synopsis   Text to add to the synopsis section
##
sub addSynopsis {
  my ($self, $synopsis) = assertNumArgs(2, @_);
  $self->{synopsis} .= "   $synopsis";
  $self->{_currSection} = \$self->{synopsis};
}

######################################################################
# Set the author of this file
#
# @param author   The author of this file
##
sub setAuthor {
  my ($self, $author) = assertNumArgs(2, @_);
  $self->{author} = $author;
}

######################################################################
# Set the current indentation level
#
# @param dir    Either '+' or '-' to increment or decrement the
#               indentation level.
#
# @return An error message describing the failure, on undef if the
#         operation was successful
##
sub setLevel {
  my ($self, $dir) = assertNumArgs(2, @_);
  if ($dir eq '+') {
    $self->{_currLevel}++;
    ${$self->{_currSection}} .= "=over 4\n\n";
  } elsif ($dir eq '-') {
    if ($self->{_currLevel} > 0) {
      $self->{_currLevel}--;
      ${$self->{_currSection}} .= "=back\n\n";
    } else {
      return "Attempt to decrement level from level 0";
    }
  } else {
    return "Illegal level argument: $dir";
  }
  return undef;
}

######################################################################
# Set the version of this file.
#
# @param version   A string describing the version of this file
##
sub setVersion {
  my ($self, $version) = assertNumArgs(2, @_);
  $self->{version} = $version;
}

######################################################################
# Generate the POD to describe this file
#
# @return A string of the POD describing this file
##
sub toString {
  my ($self) = assertNumArgs(1, @_);

  my $output = "=head1 NAME\n\n";
  $output .= "$self->{name} - $self->{summary}\n\n";
  if ($self->{synopsis}) {
    $output .= "=head1 SYNOPSIS\n\n$self->{synopsis}\n\n";
  }
  if ($self->{description}) {
    $output .= "=head1 DESCRIPTION\n\n$self->{description}\n\n";
  }
  if ($self->{functions}) {
    $output .= "=head1 FUNCTIONS\n\n";
    foreach my $function (@{$self->{functions}}) {
      $output .= $function->toString();
    }
  }
  if ($self->{bugs}) {
    $output .= "=head1 BUGS\n\n$self->{bugs}\n\n";
  }
  if ($self->{version}) {
    $output .= "=head1 VERSION\n\n$self->{version}\n\n";
  }
  $output .= "=head1 AUTHOR\n\n$self->{author}\n\n";
  return $output;
}

1;
