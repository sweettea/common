# Makefile for all perl modules
#
# $Id$

ROOT := ..

PWD:= $(shell pwd)
LIB:= ${PWD}/lib
DESTDIR:= ${PWD}/build

SUBDIRS:= third
CHECKIN_SUBDIRS := Permabit
SYMLINKS:= Permabit Pdoc
DOCTREES:=					\
	Pdoc					\
	Permabit				\
	bin

TOOLS_BIN:=../tools/bin

# MakeMaker, which all projects in third/ use, installs man pages to
# a subdirectory of third/; it is the subdirectory formed by chopping
# siteprefix off the start and 'man3' off the end of installsiteman3dir.
# Therefore, mimic that chopping.
SHELLSCRIPT:=$(shell perl '-V:installsiteman3dir' '-V:siteprefix')

# This relies on each -V:name incantation printing "name=[value];" in a
# format which can be evaluated by the shell.
MANSUBDIR:=$(shell $(SHELLSCRIPT) echo $$installsiteman3dir|\
                   sed "s:^$$siteprefix::")
# We want to copy everything from third/MANSUBDIR/../.
MANDIR:=third$(MANSUBDIR)/../
$(info Expecting man files in "$(MANDIR)")

all: ${LIB} ${SUBDIRS} symlinks

# Add all dirs in ${SUBDIRS} here
third:
	${MAKE} -C $@

${LIB}:
	mkdir -p $@

symlinks: ${LIB}
	set -e; for link in ${SYMLINKS}; do \
	  rm -rf ${LIB}/$$link; \
	  ln -s ../$$link ${LIB}/$$link; \
	done

doc:
	for dir in ${DOCTREES}; do \
	  mkdir -p ${DESTDIR}/$$dir; \
	  ${MAKE} -C $$dir $@ DESTDIR=${DESTDIR}/$$dir; \
	done
	if [ -d ${TOOLS_BIN} ]; then \
	   mkdir -p ${DESTDIR}/tools/bin; \
	   ${MAKE} -C ${TOOLS_BIN} $@ DESTDIR=${DESTDIR}/tools/bin; \
	fi
	./bin/genPdocIndex.pl ${DESTDIR}

man:
	for dir in ${DOCTREES}; do \
	  ${MAKE} -C $$dir $@; \
	done
	cp -rp ${MANDIR}/* ${DESTDIR}

check:  do-check


do-check:
	for dir in ${DOCTREES}; do \
	  ${MAKE} -C $$dir check || exit 1; \
	done

doc-clean:
	for dir in ${DOCTREES}; do \
	  ${MAKE} -C $$dir clean; \
	done

dir-clean: doc-clean
	for dir in ${SUBDIRS}; do \
	  ${MAKE} -C $$dir clean; \
	done
	for link in ${SYMLINKS}; do \
	  rm -rf ${LIB}/$$link; \
	done

lib-clean:
	rm -rf ${LIB}

clean all-clean: lib-clean dir-clean

checkin: $(patsubst %,%-checkin,${CHECKIN_SUBDIRS})

%-checkin:
	${MAKE} -C $(patsubst %-checkin,%,$@) checkin

jenkins:
	mkdir -p ${ROOT}/logs/perltests
	$(MAKE) -j$(grep -c processor /proc/cpuinfo) \
		SAVELOGS=1 LOGDIR=$(realpath -e ${ROOT}/logs/perltests) \
	  checkin
	# A separate step to avoid spurious filecopier failures.
	$(MAKE) -j$(grep -c processor /proc/cpuinfo)               \
	  DESTDIR=$(realpath -e ./man) man

TAGS:
	find . -name '*.p[lm]' -print | etags -

.PHONY:: all third doc symlinks check checkin TAGS critic
.PHONY:: clean all-clean lib-clean dir-clean doc-clean do-check do-critic
.PHONY:: jenkins
