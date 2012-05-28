SHELL = /bin/sh
PREFIX = /usr

all:

install:
	install -d ${DESTDIR}/etc
	install --mode=644 etc/* ${DESTDIR}/etc
	install -d ${DESTDIR}/usr/sbin
	install --mode=755 sbin/*.sh ${DESTDIR}/usr/sbin
