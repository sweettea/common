# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright Red Hat
#

import os
import re
import string

########################################################################
class LSB(object):
  """Base class providing assembly of requested lsb_release-like info.

  Note that "LSB Version" is not provided; "Version" is provided in
  its place in order to preserve the field counts and relative positioning
  of lsb_release's output, particularly for the case of producing "short"
  output.
  """
  ####################################################################
  # Public class-behavior methods
  ####################################################################
  @classmethod
  def makeLSB(cls, args):

    rawData = cls._getRawData()
    return { "centos" : CentOSLSB,
             "fedora" : FedoraLSB,
             "rhel"   : RhelLSB }[cls._getDistribution(rawData)](rawData, args)

  ####################################################################
  # Public instance-behavior methods
  ####################################################################
  @property
  def info(self):
    info = []

    infoDict = self._getInfo()

    # The order is the same as that produced by lsb_release.
    # This is of importance when producing short output as that is simply
    # the data values w/o any labels.
    if self._args.reportVersion:
      info.append(self._formatVersion(infoDict["version"]))
    if self._args.reportIdentifier:
      info.append(self._formatIdentifier(infoDict["identifier"]))
    if self._args.reportDescription:
      info.append(self._formatDescription(infoDict["description"]))
    if self._args.reportRelease:
      info.append(self._formatRelease(infoDict["release"]))
    if self._args.reportCodename:
      info.append(self._formatCodename(infoDict["codename"]))

    info = (os.linesep.join(info) if not self._args.useShortOutput
                                  else " ".join(info))
    return info

  ####################################################################
  # Overridden class-behavior methods
  ####################################################################

  ####################################################################
  # Overridden instance-behavior methods
  ####################################################################
  def __init__(self, rawData, args):
    super(LSB, self).__init__()
    self.__rawData = rawData
    self.__args = args

  ####################################################################
  # Protected class-behavior methods
  ####################################################################
  @classmethod
  def _getDistribution(cls, rawData):
    return cls._getLineData("ID", rawData)

  ####################################################################
  @classmethod
  def _getLineData(cls, lineId, rawData):
    # Return the data from the line with the specified lineId.
    # Leading and trailing single and double quotes are removed.
    lineId = "{0}=".format(lineId)
    for line in rawData:
      if line.startswith(lineId):
        return line[len(lineId):].strip("\"'")

  ####################################################################
  @classmethod
  def _getRawData(cls):
    rawData = []
    with open("/etc/os-release") as f:
      for line in f:
        line = line.strip()
        if len(line) > 0:
          rawData.append(line)
    return rawData

  ####################################################################
  # Protected instance-behavior methods
  ####################################################################
  @property
  def _args(self):
    return self.__args

  ####################################################################
  @property
  def _rawData(self):
    return self.__rawData

  ####################################################################
  def _formatCodename(self, codename):
    return self._formatData("" if self._args.useShortOutput else "Codename:\t",
                            codename)

  ####################################################################
  def _formatData(self, prefix, data):
    # If short output is being generated any data with embedded whitespace
    # needs to be quoted in order to delineate it as the ultimate result is
    # a single string.
    if (self._args.useShortOutput
        and any([x in data for x in string.whitespace])):
      data = "\"{0}\"".format(data)
    return "{0}{1}".format(prefix, data)

  ####################################################################
  def _formatDescription(self, description):
    return self._formatData("" if self._args.useShortOutput
                               else "Description:\t",
                            description)

  ####################################################################
  def _formatIdentifier(self, identifier):
    return self._formatData("" if self._args.useShortOutput
                               else "Distributor ID:\t",
                            identifier)

  ####################################################################
  def _formatRelease(self, release):
    return self._formatData("" if self._args.useShortOutput else "Release:\t",
                            release)

  ####################################################################
  def _formatVersion(self, version):
    return self._formatData("" if self._args.useShortOutput
                               else "Version:\t",
                            version)

  ####################################################################
  def _getCodename(self):
    codename = self._getLineData("VERSION", self._rawData)
    codename = re.search(r".*\((.+)\)", codename).group(1).replace(" ", "")
    return codename

  ####################################################################
  def _getDescription(self):
    return self._getLineData("PRETTY_NAME", self._rawData)

  ####################################################################
  def _getInfo(self):
    return { "codename"    : self._getCodename(),
             "description" : self._getDescription(),
             "identifier"  : self._getIdentifier(),
             "release"     : self._getRelease(),
             "version"     : self._getVersion() }

  ####################################################################
  def _getIdentifier(self):
    identifier = self._getLineData("NAME", self._rawData)
    identifier = identifier.rstrip("Linux").strip()
    identifier = identifier.replace(" ", "")
    return identifier

  ####################################################################
  def _getRelease(self):
    release = self._getLineData("VERSION_ID", self._rawData)
    return release

  ####################################################################
  def _getVersion(self):
    return self._getLineData("VERSION", self._rawData)

  ####################################################################
  # Private class-behavior methods
  ####################################################################

  ####################################################################
  # Private instance-behavior methods
  ####################################################################

########################################################################
########################################################################
class ReleaseAsText(object):
  """Plug-in for distributions with a single release number (i.e., not
  <major>.<minor>) to convert the release number to text.
  """
  def _getReleaseAsText(self):
    # This is only valid up to release 99.
    digitMap = { 0: "", 1: "One", 2: "Two", 3: "Three", 4: "Four",
                 5: "Five", 6: "Six", 7: "Seven", 8: "Eight", 9: "Nine" }
    tensMap = {  0: "",
                10: { 0: "Ten", 1: "Eleven", 2: "Twelve", 3: "Thirteen",
                      4: "Fourteen", 5: "Fifteen", 6: "Sixteen",
                      7: "Seventeen", 8: "Eighteen", 9: "Nineteen" },
                20: "Twenty", 30: "Thirty", 40: "Forty", 50: "Fifty",
                60: "Sixty", 70: "Seventy", 80: "Eighty", 90: "Ninety"}

    releaseNumber = int(self._getRelease())
    digit = releaseNumber % 10
    tens = (releaseNumber // 10) * 10

    if tens == 10:
      release = tensMap[tens][digit]
    else:
      release = "{0} {1}".format(tensMap[tens], digitMap[digit]).strip()

    return release

########################################################################
########################################################################
class CentOSLSB(LSB, ReleaseAsText):
  ####################################################################
  # Overridden instance-behavior methods
  ####################################################################
  def _getCodename(self):
    return self._getReleaseAsText().replace(" ", "")

  ####################################################################
  def _getDescription(self):
    return "{0} ({1})".format(self._getLineData("PRETTY_NAME", self._rawData),
                              self._getReleaseAsText())

  ####################################################################
  def _getVersion(self):
    return "{0} ({1})".format(self._getLineData("VERSION", self._rawData),
                              self._getReleaseAsText())

########################################################################
########################################################################
class FedoraLSB(LSB, ReleaseAsText):
  ####################################################################
  # Overridden instance-behavior methods
  ####################################################################
  def _getCodename(self):
    return self._getReleaseAsText().replace(" ", "")

  ####################################################################
  def _getDescription(self):
    return self._replaceParentheticalWithReleaseText(
            super(FedoraLSB, self)._getDescription())

  ####################################################################
  def _getVersion(self):
    return self._replaceParentheticalWithReleaseText(
            super(FedoraLSB, self)._getVersion())

  ####################################################################
  # Protected instance-behavior methods
  ####################################################################
  def _replaceParentheticalWithReleaseText(self, value):
    result = re.search(r"(.*\().*(\).*)", value)
    return "{0}{1}{2}".format(result.group(1),
                              self._getReleaseAsText(),
                              result.group(2))

########################################################################
########################################################################
class RhelLSB(LSB):
  pass
