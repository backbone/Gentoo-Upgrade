#!/bin/bash

kernel_regex=`kernel-config list | grep \* | cut -d" " -f6  | sed 's~[0-9]*\.[0-9]*\.[0-9]*~[0-9]*\.[0-9]*\.[0-9]*~ ; s~-r[0-9]*$~.*~'`
[ "" == "$kernel_regex" ] && echo "kernel_regex build failed ;-(" && exit -1

new_kernel=`kernel-config list | cut -d" " -f6 | grep ^$kernel_regex$ | sort -V | tail -n1`
[ "" == "$new_kernel" ] && echo "Couldn't find appropriate new kernel version ;-(" && exit -1

kernel-config set $new_kernel
[ 0 -ne $? ] && echo "kernel-config set $new_kernel failed ;-(" && exit -1

kernel-clean.sh
[ 0 -ne $? ] && echo "kernel-clean.sh failed ;-(" && exit -1

vmlinuz_file=/boot/`echo $new_kernel | sed 's~^linux~vmlinuz~'`
[ "" == "$vmlinuz_file" ] && echo "vmlinuz_file == \"\"" && exit -1

if [ ! -f "$vmlinuz_file" ]; then
	kernel-rebuild.sh
	[ 0 -ne $? ] && echo "kernel-rebuild.sh failed" && exit -1
fi

exit 0

