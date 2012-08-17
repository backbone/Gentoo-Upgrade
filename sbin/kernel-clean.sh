#!/bin/bash

NICE_CMD="nice -n 19 ionice -c2 -n7"

REVISION=`kernel-config list | grep \*$ | cut -d" " -f6 | cut -d- -f2-8`
[ "" == "$REVISION" ] && echo "No appropriate kernel revision found ;-(" && exit -1

SOURCES=linux-$REVISION
[ "" == "$SOURCES" ] && echo "No appropriate kernel sources found ;-(" && exit -1

# rm old modules
cd /lib/modules && $NICE_CMD rm -rf `ls | grep -v "^$REVISION$"`

# rm old kernel revisions
mount -o remount,rw /boot
cd /boot && rm -f `ls System.map-* config-* vmlinuz-* initramfs-* 2>/dev/null | grep -vE "$REVISION$|$REVISION.img$"`
mount -o remount,ro /boot

# rm old sources
cd /usr/src && $NICE_CMD rm -rf `find -maxdepth 1 -name "linux-*" -type d | grep -v "$SOURCES$"`

exit 0

