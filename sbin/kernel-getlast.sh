#!/bin/bash

let FORCE_REBUILD=0
KERNEL_REBUILD_ARGS=""

[ -f /etc/gentoo-upgrade.conf ] && source /etc/gentoo-upgrade.conf

# available parameters
eval set -- "`getopt -o h,q --long help,force-rebuild,mrproper,quiet -- \"$@\"`"

while true ; do
        case "$1" in
                -h|--help)
                        echo "Usage: kernel-getlast.sh [keys]..."
                        echo "Keys:"
                        echo -e "-h, --help\t\t\tShow this help and exit."
                        echo -e "--force-rebuild\t\t\tForce to rebuild kernel even if no new versions found."
                        echo -e "--mrproper\t\t\tClean kernel sources before rebuild."
                        echo -e "-q, --quiet\t\t\tMake kernel configuration non-interactive."
                        echo
                        echo -e "This program works on any GNU/Linux with GNU Baurne's shell"
                        echo -e "Report bugs to <mecareful@gmail.com>"
                        exit 0
                        ;;
                --force-rebuild) let FORCE_REBUILD=1 ; shift ;;
                --mrproper) KERNEL_REBUILD_ARGS="$KERNEL_REBUILD_ARGS --mrproper" ; shift ;;
                -q|--quiet) KERNEL_REBUILD_ARGS="$KERNEL_REBUILD_ARGS --silent" ; shift ;;
                --) shift ; break ;;
                *) echo "Internal error!" ; exit -1 ;;
        esac
done

kernel_regex=`kernel-config list | grep \* | cut -d" " -f6  | sed 's~[0-9]*\.[0-9]*\.[0-9]*~[0-9]*\.[0-9]*\.[0-9]*~ ; s~-r[0-9]*$~~; s~$~\\\(-r[0-9]\\\)\\\?~'`
[ "" == "$kernel_regex" ] && echo "kernel_regex build failed ;-(" && exit -1

new_kernel=`kernel-config list | cut -d" " -f6 | grep ^$kernel_regex$ | sort -V | tail -n1`
[ "" == "$new_kernel" ] && echo "Couldn't find appropriate new kernel version ;-(" && exit -1

# remounting file systems ro->rw
for fs in $RW_REMOUNT; do
	if [[ "$fs" =~ ^/+usr/*$ || "$fs" =~ ^/+boot/*$ ]]; then
		echo "remounting $fs -> rw"
		mount -o remount,rw $fs
		[ 0 -ne $? ] && echo "mount -o remount,rw $fs failed ;-( =======" && exit -1
	fi
done

kernel-config set $new_kernel
[ 0 -ne $? ] && echo "kernel-config set $new_kernel failed ;-(" && exit -1

kernel-clean.sh
[ 0 -ne $? ] && echo "kernel-clean.sh failed ;-(" && exit -1

vmlinuz_file=/boot/`echo $new_kernel | sed 's~^linux~vmlinuz~'`
[ "" == "$vmlinuz_file" ] && echo "vmlinuz_file == \"\"" && exit -1


if [[ ! -f "$vmlinuz_file" || 1 -eq $FORCE_REBUILD ]]; then
	kernel-rebuild.sh $KERNEL_REBUILD_ARGS
	[ 0 -ne $? ] && echo "kernel-rebuild.sh $KERNEL_REBUILD_ARGS failed" && exit -1
fi

# remounting file systems rw->ro
for fs in $RO_REMOUNT; do
	if [[ "$fs" =~ ^/+usr/*$ || "$fs" =~ ^/+boot/*$ ]]; then
		echo "remounting $fs -> ro"
		mount -o remount,ro $fs
		[ 0 -ne $? ] && echo "mount -o remount,ro $fs failed ;-( =======" && exit -1
	fi
done

exit 0

