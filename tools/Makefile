# $Id$

CHECK_SUBDIRS :=				\
	bin

all .DEFAULT:

check:
	set -e; for dir in ${CHECK_SUBDIRS}; do \
	  ${MAKE} -C $$dir $@; \
	done

doc:

clean:
	rm -f *.deb *.build *.changes
