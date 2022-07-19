# $Id$

SUBDIRS := perl tools

CHECK_SUBDIRS := perl tools

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

packages:
	$(MAKE) -C tools/installers all

jenkins:
	$(MAKE) -C perl
	$(MAKE) -j$(grep -c processor /proc/cpuinfo) check
	mkdir -p logs/perltests
	$(MAKE) -j$(grep -c processor /proc/cpuinfo) -C perl              \
	  CHECKIN_SUBDIRS=Permabit SAVELOGS=1 LOGDIR=`pwd`/logs/perltests \
	  checkin
	# A separate step to avoid spurious filecopier failures.
	$(MAKE) -j$(grep -c processor /proc/cpuinfo) -C perl              \
	  DESTDIR=`pwd`/perl/man man

.PHONY:	all clean check doc packages jenkins
