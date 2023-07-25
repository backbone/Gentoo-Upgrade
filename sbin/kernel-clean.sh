#!/bin/bash

[ -f /etc/gentoo-upgrade.conf ] && source /etc/gentoo-upgrade.conf

NICE_CMD="nice -n 19 ionice -c2"

REVISION=`kernel-config list | grep \*$ | cut -d" " -f6 | cut -d- -f2-8 | sed 's~\\+~\\\\+~g'`
[ "" == "$REVISION" ] && echo "No appropriate kernel revision found ;-(" && exit -1

UNAME=`uname -r | sed 's~\\+~\\\\+~g'`
echo UNAME=$UNAME

# remounting file systems ro->rw
for fs in $RW_REMOUNT; do
	if [[ "$fs" =~ ^/+usr/*$ || "$fs" =~ ^/+boot/*$ ]]; then
		echo "remounting $fs -> rw"
		mount -o remount,rw $fs
		[ 0 -ne $? ] && echo "mount -o remount,rw $fs failed ;-( =======" && exit -1
	fi
done

# rm old modules
echo REVISION=$REVISION
cd /lib/modules && $NICE_CMD rm -rf `ls --color=never | sort -V | grep -vE "^$REVISION$|^$REVISION-x86_64$|^$UNAME$"`

# rm old kernel revisions
mount -o remount,rw /boot
cd /boot
for f in System.map config vmlinuz kernel-genkernel initramfs; do
    rm -f `ls --color=never $f-* 2>/dev/null | sort -V | grep -vE "$REVISION$|$REVISION-x86_64$|$REVISION.img$|$REVISION-x86_64.img$|$UNAME$|$UNAME-x86_64$|$UNAME.img$|$UNAME-x86_64.img$"`
done
mount -o remount,ro -force /boot

# Updating Grub config
echo "Updating Grub menu"
if [ `which grub-mkconfig 2>/dev/null` ]; then
	[ -f /boot/grub/grub.cfg ] && grub-mkconfig -o /boot/grub/grub.cfg
	[ -f /boot/grub2/grub.cfg ] && grub-mkconfig -o /boot/grub2/grub.cfg
elif [ `which grub2-mkconfig 2>/dev/null` ]; then
	[ -f /boot/grub/grub.cfg ] && grub2-mkconfig -o /boot/grub/grub.cfg
	[ -f /boot/grub2/grub.cfg ] && grub2-mkconfig -o /boot/grub2/grub.cfg
else
	[ -f /boot/grub/grub.conf ] && \
	sed -i "s~\/boot\/vmlinuz-[0-9][^ ]*~\/boot\/vmlinuz-$REVISION~g;
	        s~\/boot\/kernel-genkernel-`uname -m`-[0-9][^ ]*~\/boot\/kernel-genkernel-`uname -m`-$REVISION~g;
	        s~\/boot\/initramfs-[0-9][^ ]*~\/boot\/initramfs-$REVISION.img~g" \
	        /boot/grub/grub.conf
fi

# rm old sources
cd /usr/src
$NICE_CMD rm -rf `find -maxdepth 1 -name "linux-*" -type d | sort -V | grep -vE "linux-$REVISION$|linux-$UNAME"`

# remounting file systems rw->ro
for fs in $RO_REMOUNT; do
	if [[ "$fs" =~ ^/+usr/*$ || "$fs" =~ ^/+boot/*$ ]]; then
		echo "remounting $fs -> ro"
		mount -o remount,ro -force $fs
		[ 0 -ne $? ] && echo "mount -o remount,ro -force $fs failed ;-( =======" && exit -1
	fi
done

exit 0

