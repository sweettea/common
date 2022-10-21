# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright Red Hat
#

import argparse

from .LSB import LSB

########################################################################
class LSBCommand(object):
  """Class providing lsb_release-like functionality.

  Note that "LSB Version" is not provided; "Version" is provided in
  its place in order to preserve the field counts and relative positioning
  of lsb_release's output, particularly for the case of producing "short"
  output.
  """
  ####################################################################
  # Public class-behavior methods
  ####################################################################

  ####################################################################
  # Public instance-behavior methods
  ####################################################################
  def run(self):
    print(LSB.makeLSB(self._getArguments()).info)

  ####################################################################
  # Overridden class-behavior methods
  ####################################################################

  ####################################################################
  # Overridden instance-behavior methods
  ####################################################################
  def __init__(self):
    super(LSBCommand, self).__init__()
    self._argumentParser = argparse.ArgumentParser(
      formatter_class = argparse.RawDescriptionHelpFormatter,
      description = """
        Provides lsb_release-like functionality.

        Note that "LSB Version" is not provided; "Version" is provided in
        its place in order to preserve the field counts and relative
        positioning of lsb_release's output, particularly for the case of
        producing "short" output.

        The description text does not contain the term "release".

        In the case of Fedora the release is always returned (converted to
        text; e.g., "35" is converted to "Thirty Five") as part of both the
        description and codename rather than values dependent on the version
        (e.g., workstation or server) installed.""")

    self._argumentParser.add_argument("--all", "-a",
                                      help = "report all information",
                                      action = "store_true",
                                      dest = "reportAll")

    self._argumentParser.add_argument("--codename", "-c",
                                      help = "report codename",
                                      action = "store_true",
                                      dest = "reportCodename")

    self._argumentParser.add_argument("--description", "-d",
                                      help = "report description",
                                      action = "store_true",
                                      dest = "reportDescription")

    self._argumentParser.add_argument("--id", "-i",
                                      help = "report identifier",
                                      action = "store_true",
                                      dest = "reportIdentifier")

    self._argumentParser.add_argument("--release", "-r",
                                      help = "report release",
                                      action = "store_true",
                                      dest = "reportRelease")

    self._argumentParser.add_argument("--version", "-v",
                                      help = "report version",
                                      action = "store_true",
                                      dest = "reportVersion")

    self._argumentParser.add_argument("--short", "-s",
                                      help = "use short output",
                                      action = "store_true",
                                      dest = "useShortOutput")

  ####################################################################
  # Protected class-behavior methods
  ####################################################################

  ####################################################################
  # Protected instance-behavior methods
  ####################################################################
  def _getArguments(self):
    arguments = self._argumentParser.parse_args()
    if arguments.reportAll:
      arguments.reportCodename = True
      arguments.reportDescription = True
      arguments.reportIdentifier = True
      arguments.reportRelease = True
      arguments.reportVersion = True

    # If no specific information was requested default to version.
    arguments.reportVersion = (arguments.reportVersion
                                or (not (arguments.reportAll
                                         or arguments.reportCodename
                                         or arguments.reportDescription
                                         or arguments.reportIdentifier
                                         or arguments.reportRelease)))
    return arguments

  ####################################################################
  # Private class-behavior methods
  ####################################################################

  ####################################################################
  # Private instance-behavior methods
  ####################################################################

