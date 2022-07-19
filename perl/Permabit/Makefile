# $Id$

ROOT:=..
DOCDIRS:= AsyncTask CheckServer Future LabUtils testcases
MANPREFIX:=Permabit::

include ${ROOT}/Makefile.common

TEST_ARGS := --log --threads=10
ifeq ($(SAVELOGS),1)
  TEST_ARGS += --log=1 --xmlOutput=1
endif
ifdef LOGDIR
  TEST_ARGS += --logDir=$(LOGDIR) --saveServerLogDir=$(LOGDIR)
endif

checkin: runtests
runtests:
	./$@.pl $(TEST_ARGS)

cleanlogs:
	rm -rf testcases\:\:*
	rm -f filecopy.stdout

clean:: cleanlogs
