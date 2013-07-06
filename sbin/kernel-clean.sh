#!/bin/bash

[ -f /etc/gentoo-upgrade.conf ] && source /etc/gentoo-upgrade.conf

NICE_CMD="nice -n 19 ionice -c2"

REVISION=`kernel-config list | grep \*$ | cut -d" " -f6 | cut -d- -f2-8`
[ "" == "$REVISION" ] && echo "No appropriate kernel revision found ;-(" && exit -1

UNAME=`uname -r`
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
cd /lib/modules && $NICE_CMD rm -rf `ls --color=never | sort -V | grep -vE "^$REVISION$|^$UNAME$"`

# rm old kernel revisions
mount -o remount,rw /boot
cd /boot
for f in System.map config vmlinuz kernel-genkernel initramfs; do
    rm -f `ls --color=never $f-* 2>/dev/null | sort -V | grep -vE "$REVISION$|$REVISION.img$|$UNAME$|$UNAME.img$"`
done
mount -o remount,ro -force /boot

# updating grub menu
echo "Updating Grub menu"
[ -f /boot/grub/grub.conf ] && \
sed -i "s~\/boot\/vmlinuz-[0-9][^ ]*~\/boot\/vmlinuz-$REVISION~g;
        s~\/boot\/kernel-genkernel-`uname -m`-[0-9][^ ]*~\/boot\/kernel-genkernel-`uname -m`-$REVISION~g;
        s~\/boot\/initramfs-[0-9][^ ]*~\/boot\/initramfs-$REVISION.img~g" \
        /boot/grub/grub.conf

[ -f /boot/grub2/grub.cfg ] && grub2-mkconfig -o /boot/grub2/grub.cfg

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

