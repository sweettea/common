##
# This module contains the logic for parsing a perldoc file and
# generating pod from it.
#
# @description
#
# The Permabit tools writers have found that while pod is very handy
# for generating all sorts of nicely formatted documentation from perl
# files, actually reading the pod as pod is painful. As such, there
# has been duplication of documentation with individual functions
# having nicely formatted human readable comments and then the same
# (or similar) documentation repeated at the end of the file as
# pod. In an attempt to eliminate this duplication, we present
# perldoc, a way of formatting comments similar to (but less
# featureful than) javadoc, which this module will convert to pod for
# handy reformatting via the wealth of pod2* utilities.
#
# Perldoc comments are delimited by a string of at least 2 hash marks.
# Such a delimiter must appear at the start and end of any perldoc.
#
# Within a perldoc comment, tags, beginning with an @at@, are used to
# differentiate the text (at signs can be represented as @at@at@at@).
#
# The perldoc tags consist of several categories:
#
# @level{+}
# @item module tags, which add special characteristics to the module
# being documented.
#
# @level{+}
# @item author         The author section of the module
# @item bugs           The bugs section in the module
# @item description    A description of the module
# @item item           This tag is used within a major section to
#                      indicate an item to be delimited.
# @item level{[+/-]}   Increment (+) or decrement (-) the current indentation
#                      level for I<item> tags. The level is automatically
#                      reset to 0 at the end of a perldoc block
# @item synopsis       A synopsis of the module
# @level{-}
#
# If omitted, a default author will be provided by perldoc.
#
# @item paramList tags, which are used to document property hashes. Many
# Permabit classes use property hashes to specify a wealth of
# configuration parameters (for example, see
# C<src/perl/cliquetest/CliqueTest.pm>). A property hash is formatted
# for perldoc by enclosing the entire hash in a perldoc block,
# providing the I<paramList> tag at the beginning of the block, and
# placing a comment containing a I<ple> tag before each key of the
# hash. Perldoc will automatically pick up the key names and default values
# from the code itself.
#
# @level{+}
# @item paramList{name} Signals the start of a parameter list, <name> is
#                       the name of this list.
# @item ple             Documents a parameter in the list
# @level{-}
#
# @item Function blocks are used to document functions. Any perldoc
# block which does not begin with a tag is assumed to be a function
# block. The block must end on the line immdiately preceding the
# function definition, and perldoc will automatically extract the
# function's name.  Functions whose names begin with '_' will not be
# documented, even if they have perldoc comment blocks. Within the
# function block, the following tags may be used:
#
# @level{+}
# @item croaks       Document when this method will I<croak>
# @item confesses    Document when this method will I<confess>
# @item inherit      Note that this method is inherited
# @item param        Document a parameter
# @item oparam       Document an optional parameter
# @item params{list} Insert the documentation of the named parameter list
# @item return       Document the return value of the function (must follow
#                    all parameters
# @item see          Refer to another item.
#
# @level{-}
# @level{-}
#
# $Id$
##
package Pdoc::Generator;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);

use Carp qw(croak);
use File::Basename;
use File::Temp qw(tempfile);
use FindBin;
use Pdoc::Function;
use Pdoc::Location;
use Pdoc::Module;
use Pdoc::ParamList;
use Pdoc::Script;
use Permabit::Assertions qw(assertMinMaxArgs assertNumArgs);
use Pod::Usage;
use Storable qw(dclone);

use base qw(Exporter);

our @EXPORT_OK = qw (pdoc2help pdoc2usage);

my $BASE_RE = '(?:base|parent)';

my %basicTags = ('author'       => \&author,
                 'bugs'         => \&bugs,
                 'description'  => \&description,
                 'inherit'      => \&inherit,
                 'item'         => \&item,
                 'oparam'       => \&oparam,
                 'param'        => \&param,
                 'ple'          => \&ple,
                 'return'       => \&returnValue,
                 'see'          => \&see,
                 'confesses'    => \&confesses,
                 'croaks'       => \&croaks,
                 'synopsis'     => \&synopsis,
                 'version'      => \&version,           # GENERATED
                );

my %parameterizedTags = ('level'        => \&level,
                         'params'       => \&params,
                         'paramList'    => \&paramList,
                        );

##
# @paramList{new}
my %properties
  = (
     # @ple The filename to generate pdoc for.
     filename                   => undef,
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
  if (!$self->{filename}) {
    croak("You must supply a filename");
  }
  $self->{_paramLists} = {};
  return $self;
}

######################################################################
# Set the author of the current module.
#
# @param source         The name of the author
# @param context        The File that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub author {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'File', $source, $location);
  $context->setAuthor($source);
}

######################################################################
# Add a bugs section to this module.
#
# @param source         The bugs for this modules
# @param context        The File that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub bugs {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'File', $source, $location);
  $context->addBugs($source);
}

######################################################################
# Add a description of this module.
#
# @param source         The description of this module
# @param context        The File that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub description {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'File', $source, $location);
  $context->addDescription($source);
}

######################################################################
# Inherit doc from the overridden method in the superclass.
#
# @param source         Ignored
# @param context        The Function that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub inherit {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'Function', $source, $location);
  $context->inheritDoc();
}

######################################################################
# Add an item to the current block
#
# @param source         The item to add
# @param context        The File that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub item {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'File', $source, $location);
  if ($source =~ /^\s*(\S+)\s+(.*)$/s) {
    $context->addItem($1, $2);
  } else {
    parseError($location, "Couldn't parse item tag out of: $source");
  }
}

######################################################################
# Generate a short synopsis of this module.
#
# @param source         Synopsis of this module
# @param context        The File that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub synopsis {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'File', $source, $location);
  $context->addSynopsis($source);
}

######################################################################
# Add a new entry to the current parameter list.
#
# @at@ple tags are of the format:
#     # @at@ple Description of parameter
#     # More commentary
#     foo => 0,
#
# @param source         The source that should be parsed into a ple.
# @param context        The ParamList that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub ple {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'ParamList', $source, $location);
  if ($source =~ /(.*)\s+(\S+)\s+=>/s) {
    my ($text, $paramName) = ($1, $2);
    $context->addParameter($paramName, $text);
  } else {
    parseError($location, "Couldn't parse ple tag out of: $source");
  }
}

######################################################################
# Add a new parameter to the current function
#
# @at@param tags are of the format:
#     # @at@param parameter Description of parameter
#     # More commentary
#
# @param source         The source that should be parsed into a param.
# @param context        The Function that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub param {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'Function', $source, $location);
  if ($source =~ /^\s*(\S+)\s+(.*)$/s) {
    my ($paramName, $text) = ($1, $2);
    $context->addParameter($paramName, $text);
  } else {
    parseError($location, "Couldn't parse param tag out of: $source");
  }
}

######################################################################
# Add a new optional parameter to the current function.
#
# @at@oparam tags are of the format:
#     # @at@oparam parameter Description of parameter
#     # More commentary
#
# @param source         The source that should be parsed into a oparam.
# @param context        The Function that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub oparam {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'Function', $source, $location);
  if ($source =~ /^\s*(\S+)\s+(.*)$/s) {
    my ($paramName, $text) = ($1, $2);
    $context->addOptionalParameter($paramName, $text);
  } else {
    parseError($location, "Couldn't parse param tag out of: $source");
  }
}

######################################################################
# Add the return value for the current function
#
# @at@return tags are of the format:
#     # @at@return Description of return value
#     # More commentary
#
# @param source         The text of the return value statement.
# @param context        The Function that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub returnValue {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'Function', $source, $location);
  $context->addReturnValue($source);
}

######################################################################
# Add a reference.
#
# @at@see tags are of the format:
#     # @at@see function
#
# @param source         The text of the return value statement.
# @param context        The Function that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub see {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'Function', $source, $location);
  $context->addSee($source);
}

######################################################################
# Document when the current function will C<croak>.
#
# @at@croaks tags are of the format:
#     # @at@croaks Description of deadly conditions
#     # More commentary
#
# @param source         The text of the croaking conditions.
# @param context        The Function that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub croaks {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'Function', $source, $location);
  $context->addCroak($source);
}

######################################################################
# Document when the current function will C<confess>.
#
# @at@confesses tags are of the format:
#     # @at@confesses Description of deadly conditions
#     # More commentary
#
# @param source         The text of the croaking conditions.
# @param context        The Function that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub confesses {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'Function', $source, $location);
  $context->addConfess($source);
}

######################################################################
# Mark that we're starting a new parameter list.
#
# @param listName       Name of the list
# @param source         Ignored
# @param context        The File that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
#
# @return A new ParamList Context
##
sub paramList {
  my ($self, $listName, $source, $context, $location) = assertNumArgs(5, @_);
  assertType($context, 'File', $source, $location);
  if ($self->{_paramLists}->{$listName}) {
    parseError($location, "Duplicate definition of paramlist $listName\n");
  }
  my $list = Pdoc::ParamList->new($listName);
  $self->{_paramLists}->{$listName} = $list;
  return $list;
}

######################################################################
# Insert the previously declared parameter list of the given name.
#
# @param listName       Name of the list
# @param source         Ignored
# @param context        Must be undef
# @param location       The location this tag was found
#
# @return The current context
##
sub params {
  my ($self, $listName, $source, $context, $location) = assertNumArgs(5, @_);
  assertType($context, 'Function', $source, $location);
  my $list = $self->{_paramLists}->{$listName};
  if (!$list) {
    parseError($location, "Unknown parameter list $listName");
  }
  $list->insertInFunction($context);

  return $context;
}

######################################################################
# Increment or decrement the current level of indentation.
#
# @param dir            Either '+' or '-' to increment or decrement
#                       the current level of indentation.
# @param source         Ignored
# @param context        The File that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub level {
  my ($self, $dir, $source, $context, $location) = assertNumArgs(5, @_);
  assertType($context, 'File', $source, $location);
  my $errMsg = $context->setLevel($dir);
  if ($errMsg) {
    parseError($location, $errMsg);
  }
  return $context;
}

######################################################################
# Generate the version section of this module.
#
# @param source         The version of this module
# @param context        The File that was being parsed when this tag
#                       was encountered.
# @param location       The location this tag was found
##
sub version {
  my ($self, $source, $context, $location) = assertNumArgs(4, @_);
  assertType($context, 'File', $source, $location);
  $context->setVersion($source);
}

######################################################################
# Assert that the current context is of the given type
#
# @param context        The current context
# @param type           The correct type for the current context
# @param source         The source being parsed
# @param location       The location this source was found
##
sub assertType {
  my ($context, $type, $source, $location) = assertNumArgs(4, @_);
  $type = "Pdoc::$type";
  if (!$context || !$context->isa($type)) {
    parseError($location, "Parameter " . ref($context)
               . " is not a $type when parsing:\n$source");
  }
}

######################################################################
# Handle a parsing error
#
# @param location       The location the parsing error occurred
# @param message        The message to be displayed
#
# @croaks with the given location and message
##
sub parseError {
  my ($location, $message) = assertNumArgs(2, @_);
  die($location->toString() . "warning: " . $message . "\n");
}

######################################################################
# Generate documentation for the current doc block.
#
# @param currentDoc     The current block of documentation
# @param context        The Context for this block of documentation
# @param location       The current location.
##
sub parseSections {
  my ($self, $currentDoc, $context, $location) = assertNumArgs(4, @_);

  # Temporarily replace @ at beginning of line with a \007.
  $currentDoc =~ s/\n@/\n\007/g;
  # Then replace @at@ with @ (including those already converted to \007).
  $currentDoc =~ s/[@\007]at@/@/g;
  # Convert '$Id VERSION $' to @version VERSION (and avoid having the
  # rcs keyword expanded in our own code)
  $currentDoc =~ s|\044Id: (.*)\044|\007version $1|;

  my $firstSection = 1;
  # Now split into sections on the \007s
  my @sections = split("\007", $currentDoc);

  foreach my $section (@sections) {
    if ($firstSection) {
      # Strip off leading whitespace
      $section =~ s|^\s+||;
      if (!$context) {
        parseError($location, "No header pdoc found before summary");
      }
      $context->addSummary($section);
      $firstSection = 0;
    } elsif ($section =~ /^([^\s\{\$]+)(\{(\S+)\})(.*)$/s) {
      # Handle parameterized tags of the form @tag{param} text
      my ($tagName, $parameter, $source) = ($1, $3, $4);
      if (!$parameterizedTags{$tagName}) {
        parseError($location, "Not a valid pdoc parameterized tag: '$tagName'"
                   . " in section: '$section'");
      }
      my $operation = $parameterizedTags{$tagName};
      $context = &$operation($self, $parameter, $source, $context, $location);
    } elsif ($section =~ /^(\S+)\s+(.*)/s) {
      # Handle basic tags of the form @tag text
      my ($tagName, $source) = ($1, $2);
      if (!$basicTags{$tagName}) {
        parseError($location,
                   "Not a valid pdoc tag: '$tagName' in section: '$section' ");
      }
      my $operation = $basicTags{$tagName};
      &$operation($self, $source, $context, $location);
    }
  }
}

######################################################################
# Generate and return POD text for this file.
#
# @return the text of POD for the file.
##
sub generatePod {
  my ($self) = assertNumArgs(1, @_);
  my $fileContext;
  my @contextStack;
  my $inDoc = 0;
  my $currentDoc = '';

  open(FILE, $self->{filename})
    || croak("couldn't open $self->{filename}: $ERRNO");
  my $location = Pdoc::Location->new($self->{filename});
  while (my $line = <FILE>) {
    $location->advanceLine();
    while ($line) {
      if ($line =~ /^##/s) {
        # We've found at least 2 leading #'s
        $line = "\n";
        if ($inDoc) {
          # This is the end of a doc section
          my $nextLine = <FILE>;
          $location->advanceLine();
          if (!defined($nextLine)) {
            last;
          } elsif ($nextLine =~ /^sub (\S+)/s) {
            # It's a function comment
            if (!$fileContext) {
              parseError($location, "No header pdoc found");
            }
            unshift(@contextStack, Pdoc::Function->new($1, $fileContext));
          } elsif ($nextLine =~ m|^package (\S+);|) {
            # It's a module comment
            $fileContext = Pdoc::Module->new(name => $1);
            unshift(@contextStack, $fileContext);
          }
          # We've reached the end of a doc block, let's print it out.
          $self->parseSections($currentDoc, $contextStack[0], $location);
          $currentDoc = '';
        }
        $inDoc = !$inDoc;
      } elsif ($inDoc) {
        if ($line !~ /^\s*#/) {
          if ($line =~ /^sub (\S+)(.*)$/s) {
            parseError($location,
                       "Improperly terminated pdoc for function '${1}()'");
          }

          # Don't barf on @ signs in non-comment lines within comment
          # blocks (eg, within paramlists).
          $line =~ s|\@|\@at\@|g;
        }
        $line =~ s|^\s*#\s||;
        ($line) || ($line = "\n");
        $currentDoc .= $line;
        $line = '';
      } elsif (($location->getLineNumber() == 1)
               && ($line =~ m|^\#!/usr/bin/perl|)) {
        $fileContext = Pdoc::Script->new(name => basename($self->{filename}));
        unshift(@contextStack, $fileContext);
        $line = '';
      } else {
        if ($line =~ m|^sub (\S+)|s) {
          if (!$fileContext) {
            parseError($location, "Function $1 found without finding"
                       . " module declaration");
          }
          unshift(@contextStack, Pdoc::Function->new($1, $fileContext));
          $contextStack[0]->addSummary("No pdoc found");
        } elsif ($line =~ m|^use $BASE_RE\s+qw\(([^)]*)(\))?|) {
          if (!$fileContext) {
            parseError($location, "No header pdoc found");
          }
          my @bases = split(' ', $1);
          my $foundBase = $bases[0];
          if ($foundBase) {
            $fileContext->setBase($foundBase);
          }
          my $foundCloseParen = $2;
          while (!$foundCloseParen) {
            my $nextLine = <FILE>;
            $location->advanceLine();
            if ($nextLine =~ m|\s*([^)]*)(\))?|) {
              if (!$foundBase) {
                @bases = split(' ', $1);
                $foundBase = $bases[0];
                if ($foundBase) {
                  $fileContext->setBase($foundBase);
                }
              }
              $foundCloseParen = $2;
            }
          }
        } elsif (($line =~ m|^\}|)
                 && $contextStack[0]->isa("Pdoc::Function")) {
          shift(@contextStack);
        }
        $line = '';
      }
    }
  }
  close(FILE) || croak("Unable to close $self->{filename}");

  if (!$fileContext) {
    croak("No pdoc found in $self->{filename}");
  }
  return $fileContext->toString();
}

##########################################################################
# Extract the pod from the given file into a temporary file.
#
# @param script         The full path to the script to extract the pod for.
#
# @return a file handle to a temporary file
##
sub extractPod {
  my ($script)    = assertNumArgs(1, @_);
  my $generator   = Pdoc::Generator->new(filename => $script);
  my ($fh, undef) = tempfile(UNLINK => 1);
  print $fh $generator->generatePod();
  seek($fh, 0, 0);
  return $fh;
}

##########################################################################
# Call L<Pod::Usage/pod2usage> on the pod of a script with options
# appropriate for generating the full documentation for this script
# then exiting with error code 1.  Text will go to STDOUT.
#
# @oparam script        The full path to the script to generate a
#                       usage message for.  Defaults to the currently
#                       running script.
##
sub pdoc2help {
  my ($script) = assertMinMaxArgs(0, 1, @_);
  $script ||= "$FindBin::Bin/$FindBin::Script";
  my $fh = extractPod($script);
  pod2usage({ -input    => $fh,
              -exitval  => 1,
              -output   => \*STDOUT,
              -verbose  => 2,
            });
  close($fh);
}

##########################################################################
# Call L<Pod::Usage/pod2usage> on the pod of a script with options
# appropriate for generating a usage message (the text of the
# @at@synopsis section) then exiting with exit code 2.  Text will go
# to STDERR.
#
# @oparam script        The full path to the script to generate a
#                       usage message for.  Defaults to the currently
#                       running script.
##
sub pdoc2usage {
  my ($script) = assertMinMaxArgs(0, 1, @_);
  $script ||= "$FindBin::Bin/$FindBin::Script";
  my $fh = extractPod($script);
  pod2usage({ -input    => $fh,
              -exitval  => 2,
              -output   => \*STDERR,
              -verbose  => 1,
            });
  close($fh);
}

1;
