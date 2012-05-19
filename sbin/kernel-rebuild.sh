#!/bin/bash

SILENT=false

# available parameters
eval set -- "`getopt -o hs --long help,silent -- \"$@\"`"

while true ; do
        case "$1" in
                -h|--help)
                        echo "Usage: kernel-rebuild.sh [keys]..."
                        echo "Keys:"
                        echo -e "-h, --help\tShow this help and exit."
                        echo -e "-s, --silent \tMake with silentoldconfig."
                        echo
                        echo -e "This program works on any GNU/Linux with GNU Baurne's shell"
                        echo -e "Report bugs to <mecareful@gmail.com>"
                        exit 0
                        ;;
		-s|--silent) SILENT=true ; shift ;;
	--) shift ; break ;;
	*) echo "Internal error!" ; exit -1 ;;
        esac
done

CONFIG_FILE=/proc/config.gz
[ "$1" != "" ] && CONFIG_FILE=$1

cd /usr/src/linux
[ "$?" != "0" ] && echo /usr/src/linux doesn\'t exist && exit -1

zcat $CONFIG_FILE >.config 2>/dev/null || cat $CONFIG_FILE >.config
[ "$?" != "0" ] && echo $CONFIG_FILE doesn\'t exist && exit -1

if [ true == "$SILENT" ]; then
        yes "" | make silentoldconfig
        [ "$?" != "0" ] && echo "======= yes \"\" | make silentoldconfig failed ;-( =======" && exit -1
else
        make MENUCONFIG_MODE=single_menu MENUCONFIG_COLOR=mono menuconfig
        [ "$?" != "0" ] && echo "======= make menuconfig failed ;-( =======" && exit -1
fi

# disable distcc for -march=native -mtune=native

grep 'CONFIG_X86_MARCH_NATIVE=y' .config &>/dev/null
jobs=$((`grep "^processor" /proc/cpuinfo -c`+1))
if [[ "$?" == 0 ]]; then
	make -j$jobs
	[ 0 -ne $? ] && echo "Kernel build failed ;-(" && exit -1
else
	# pump make -j$((jobs*3)) || make -j$jobs
	make -j$jobs
	[ 0 -ne $? ] && echo "Kernel build failed ;-(" && exit -1
fi

mount -o remount,rw /boot

make install
make modules_install

REVISION=`cat /usr/src/linux/include/config/kernel.release`
sed -i "s~\/boot\/vmlinuz-[23][^ ]*~\/boot\/vmlinuz-$REVISION~g" /boot/grub/grub.conf

mount -o remount,ro /boot

echo "--------- Rebuilding kernel modules ---------"
emerge -1qv @module-rebuild
[ 0 -ne $? ] && echo "Upgrading kernel modules failed ;-(" && exit -1

cd $pwdtmp 

exit 0

