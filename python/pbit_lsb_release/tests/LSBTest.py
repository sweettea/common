#!/usr/bin/env python3

# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright Red Hat
#

import os
import subprocess
import unittest

class Test_LSB(unittest.TestCase):
  ####################################################################
  def test_all(self):
    command = ["../lsb_release", "--all"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    # Don't include the empty line from the terminal line separator.
    lines = [x for x in stdout.split(os.linesep) if x != ""]
    self.assertEqual(len(lines), 5)
    self.assertTrue(lines[0].startswith("Version:"))
    self.assertTrue(lines[1].startswith("Distributor ID:"))
    self.assertTrue(lines[2].startswith("Description:"))
    self.assertTrue(lines[3].startswith("Release:"))
    self.assertTrue(lines[4].startswith("Codename:"))

    command = ["../lsb_release", "-a"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    # Don't include the empty line from the terminal line separator.
    lines = [x for x in stdout.split(os.linesep) if x != ""]
    self.assertEqual(len(lines), 5)
    self.assertTrue(lines[0].startswith("Version:"))
    self.assertTrue(lines[1].startswith("Distributor ID:"))
    self.assertTrue(lines[2].startswith("Description:"))
    self.assertTrue(lines[3].startswith("Release:"))
    self.assertTrue(lines[4].startswith("Codename:"))

  ####################################################################
  def test_codename(self):
    command = ["../lsb_release", "--codename"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(stdout.startswith("Codename:"))

    command = ["../lsb_release", "-c"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(stdout.startswith("Codename:"))

  ####################################################################
  def test_default(self):
    command = ["../lsb_release"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(stdout.startswith("Version:"))

  ####################################################################
  def test_description(self):
    command = ["../lsb_release", "--description"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(stdout.startswith("Description:"))

    command = ["../lsb_release", "-d"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(stdout.startswith("Description:"))

  ####################################################################
  def test_id(self):
    command = ["../lsb_release", "--id"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(stdout.startswith("Distributor ID:"))

    command = ["../lsb_release", "-i"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(stdout.startswith("Distributor ID:"))

  ####################################################################
  def test_release(self):
    command = ["../lsb_release", "--release"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(stdout.startswith("Release:"))

    command = ["../lsb_release", "-r"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(stdout.startswith("Release:"))

  ####################################################################
  def test_short(self):
    command = ["../lsb_release", "--all", "--short"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    # Don't include the empty line from the terminal line separator.
    lines = [x for x in stdout.split(os.linesep) if x != ""]
    self.assertEqual(len(lines), 1)

    command = ["../lsb_release", "--all", "-s"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    # Don't include the empty line from the terminal line separator.
    lines = [x for x in stdout.split(os.linesep) if x != ""]
    self.assertEqual(len(lines), 1)

    command = ["../lsb_release", "--codename", "--short"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(not stdout.startswith("Codename:"))

    command = ["../lsb_release", "--codename", "-s"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(not stdout.startswith("Codename:"))

    command = ["../lsb_release", "--short"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(not stdout.startswith("Version:"))

    command = ["../lsb_release", "-s"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(not stdout.startswith("Version:"))

    command = ["../lsb_release", "--description", "--short"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(not stdout.startswith("Description:"))

    command = ["../lsb_release", "--description", "-s"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(not stdout.startswith("Description:"))

    command = ["../lsb_release", "--id", "--short"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(not stdout.startswith("Distributor ID:"))

    command = ["../lsb_release", "--id", "-s"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(not stdout.startswith("Distributor ID:"))

    command = ["../lsb_release", "--release", "--short"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(not stdout.startswith("Release:"))

    command = ["../lsb_release", "--release", "-s"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(not stdout.startswith("Release:"))

    command = ["../lsb_release", "--version", "--short"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(not stdout.startswith("Version:"))

    command = ["../lsb_release", "--version", "-s"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(not stdout.startswith("Version:"))

  ####################################################################
  def test_version(self):
    command = ["../lsb_release", "--version"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(stdout.startswith("Version:"))

    command = ["../lsb_release", "-v"]
    lsb = subprocess.Popen(command, stdout = subprocess.PIPE)
    (stdout, _) = lsb.communicate()
    self.assertEqual(lsb.returncode, 0)
    stdout = stdout.decode()
    self.assertTrue(stdout.startswith("Version:"))

######################################################################
######################################################################
if __name__ == "__main__":
  unittest.main()
