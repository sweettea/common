# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright Red Hat
#

ROOT := ../..
include ${ROOT}/Makefile.common

PYTHON_MODULES += $(wildcard *.py)
PYTHON_TEST_MODULES := $(PYTHON_MODULES:.py=)

all check clean dist doc:

$(PYTHON_TEST_MODULES):
	PYTHONDONTWRITEBYTECODE=true python $@.py

checkin: $(PYTHON_TEST_MODULES)

jenkins: checkin

.PHONY: all check checkin clean dist doc jenkins
