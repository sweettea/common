# Makefile for all perl modules
#
# $Id: //eng/main/src/perl/third/Makefile#17 $

PWD:= $(shell pwd)
LIB:= ${PWD}/../lib

SUBDIRS:=

all: ${SUBDIRS}

${SUBDIRS}:
	${MAKE} $@/Makefile
	${MAKE} -C $@
	${MAKE} -C $@ install

%/Makefile: %/Makefile.PL
	cd ${@D};					\
	perl Makefile.PL PERL="/usr/bin/perl -I${LIB}"	\
		LIB=${LIB} PREFIX=${PWD} < /dev/null;

clean: regen-makefiles
	for dir in ${SUBDIRS}; do		\
	  ${MAKE} -C $$dir clean;		\
	done

regen-makefiles:
	for dir in ${SUBDIRS}; do		\
	  rm -f $$dir/Makefile;			\
	  ${MAKE} $$dir/Makefile;		\
	done

.PHONY:: ${SUBDIRS} all clean regen-makefiles
