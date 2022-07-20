#!/usr/bin/env python3

# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright Red Hat
#

import functools
import os
import platform
import setuptools
import sys

package_name = "pbit_lsb_release"

def prefixed(src):
  if ("bdist_wheel" not in sys.argv) or ("--universal" not in sys.argv):
    src = python_prefixed(src)
  return src

def python_prefixed(src):
  return "{0}-{1}".format(versioned("python"), src)

def versioned(src):
  python_version = platform.python_version_tuple()[0]
  if ("bdist_wheel" in sys.argv) and ("--universal" in sys.argv):
    python_version = ""
  return "{0}{1}".format(src, python_version)


setup = functools.partial(
          setuptools.setup,
          name = python_prefixed(package_name),
          version = "1.0.0",
          description = python_prefixed(package_name),
          author = "Joe Shimkus",
          author_email = "jshimkus@redhat.com",
          packages = setuptools.find_packages(exclude = []),
          entry_points = {
            "console_scripts" :
              "{0} = src:lsb_command".format(versioned("pbit_lsb_release"))
          },
          install_requires = [prefixed("setuptools")],
          zip_safe = False
        )

# Execute setup.
setup()
