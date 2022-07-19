# $Id$

SUBDIRS := perl python tools

CHECK_SUBDIRS := perl python tools
JENKINS_SUBDIRS := perl python

all clean doc TAGS:
	set -e;					\
	for i in $(SUBDIRS); do			\
		$(MAKE) -C $$i $@;		\
	done

check:
	set -e;					\
	for i in $(CHECK_SUBDIRS); do		\
		$(MAKE) -C $$i $@;		\
	done

jenkins: all
	$(MAKE) -j$(grep -c processor /proc/cpuinfo) check
	set -e;					\
	for i in $(JENKINS_SUBDIRS); do		\
		$(MAKE) -C $$i $@;		\
	done

.PHONY:	all clean check doc jenkins
