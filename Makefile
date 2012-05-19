SHELL = /bin/sh
PREFIX = /usr

all:

install:
	install -d /usr/sbin
	install --mode=755 sbin/*.sh ${DESTDIR}/usr/sbin
