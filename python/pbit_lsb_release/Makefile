# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright Red Hat
#

ROOT := ..
include ${ROOT}/Makefile.common

SUBDIRS = tests

PYLINT_ARGS    += --additional-builtins=_
PYTHON_MODULES += $(wildcard *.py)

all check clean dist doc:

checkin jenkins:
	set -e;					\
	for d in $(SUBDIRS); do			\
		$(MAKE) -C $$d $@;		\
	done

.PHONY: all check checkin clean dist doc jenkins
