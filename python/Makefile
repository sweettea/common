# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright Red Hat
#

SUBDIRS = pbit_lsb_release

.PHONY: all check checkin clean dist doc jenkins
all check checkin clean dist doc jenkins:
	set -e;					\
	for d in $(SUBDIRS); do			\
		$(MAKE) -C $$d $@;		\
	done

.PHONY: cleanall
cleanall: clean
