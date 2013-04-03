#!/bin/bash

[ -f /etc/gentoo-upgrade.conf ] && source /etc/gentoo-upgrade.conf

NICE_CMD="nice -n 19 ionice -c2"

REVISION=`kernel-config list | grep \*$ | cut -d" " -f6 | cut -d- -f2-8`
[ "" == "$REVISION" ] && echo "No appropriate kernel revision found ;-(" && exit -1

SOURCES=linux-$REVISION
[ "" == "$SOURCES" ] && echo "No appropriate kernel sources found ;-(" && exit -1

# remounting file systems ro->rw
for fs in $RW_REMOUNT; do
	if [[ "$fs" =~ ^/+usr/*$ || "$fs" =~ ^/+boot/*$ ]]; then
		echo "remounting $fs -> rw"
		mount -o remount,rw $fs
		[ 0 -ne $? ] && echo "mount -o remount,rw $fs failed ;-( =======" && exit -1
	fi
done

# rm old modules
cd /lib/modules && $NICE_CMD rm -rf `ls | grep -v "^$REVISION$"`

# rm old kernel revisions
mount -o remount,rw /boot
cd /boot && rm -f `ls System.map-* config-* vmlinuz-* kernel-genkernel-* initramfs-* 2>/dev/null | grep -vE "$REVISION$|$REVISION.img$"`
mount -o remount,ro -force /boot

# rm old sources
cd /usr/src && $NICE_CMD rm -rf `find -maxdepth 1 -name "linux-*" -type d | grep -v "$SOURCES$"`

# remounting file systems rw->ro
for fs in $RO_REMOUNT; do
	if [[ "$fs" =~ ^/+usr/*$ || "$fs" =~ ^/+boot/*$ ]]; then
		echo "remounting $fs -> ro"
		mount -o remount,ro -force $fs
		[ 0 -ne $? ] && echo "mount -o remount,ro -force $fs failed ;-( =======" && exit -1
	fi
done

exit 0

