#!/bin/bash

STAGE=1

source /etc/make.conf
[ -f /etc/gentoo-upgrade.conf ] && source /etc/gentoo-upgrade.conf

# available parameters
eval set -- "`getopt -o hs: --long help,stage: -- \"$@\"`"

while true ; do
        case "$1" in
                -h|--help)
                        echo "Usage: upgrade-gentoo.sh [keys]..."
                        echo "Keys:"
                        echo -e "-h, --help\t\t\tShow this help and exit."
                        echo -e "-s [STAGE], --stage [STAGE]\t Go to STAGE upgrade level."
                        echo
                        echo -e "This program works on any GNU/Linux with GNU Baurne's shell"
                        echo -e "Report bugs to <mecareful@gmail.com>"
                        exit 0
                        ;;
		-s|--stage) STAGE=$2 ; shift 2 ;;
	--) shift ; break ;;
	*) echo "Internal error!" ; exit -1 ;;
        esac
done

function in_list()
{
        [ -z "$1" ] && return 1

        elem=$1
        shift 1
        list=($@)

        for i in ${list[@]}; do
                [ $i == $elem ] && return 0
        done

        return 1
}

TRUE_LIST=(TRUE True true YES Yes yes 1)
FALSE_LIST=(FALSE False false NO No no 0)

# Stage 1: sync portage tree
if [ 1 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: sync portage tree ======="
	SYNC_TYPE=
	expr match "$SYNC" "git://" >/dev/null && SYNC_TYPE=git
	expr match "$SYNC" "rsync://" >/dev/null && SYNC_TYPE=rsync
	if [[ "rsync" == "$SYNC_TYPE" && 0 -ne `expr match "$PORTAGE_RSYNC_EXTRA_OPTS" ".*rsync.excludes"` ]]; then
        	# generate portage exclude list
        	RSYNC_EXCLUDES_FILE=/etc/portage/rsync.excludes
        	echo "Generating $RSYNC_EXCLUDES_FILE list..."
        	ninstalled=0
        	installed=
        	for p in `qlist -IC`; do
        		installed[ninstalled]=$p
        		let ninstalled++
        	done

        	idx=0
        	cd /usr/portage/
        	[ 0 -ne $? ] && echo "Stage $STAGE: /usr/portage/ does not exist ;-( =======" && exit $STAGE

        	echo -n >$RSYNC_EXCLUDES_FILE
        	dir_list=`ls -1 --color=never -d *-*/ virtual/ | sed 's~/$~~' | sort`
        	for d in $dir_list ; do
        		d=${d%/}
        		if [[ `qlist -IC $d | wc -l` == 0 ]]; then
        			echo $d/ >>$RSYNC_EXCLUDES_FILE
        			echo metadata/cache/$d/ >>$RSYNC_EXCLUDES_FILE
        		else
        			pn_list=`ls -1 --color=never -d ${d}/*/ | sed 's~/$~~' | sort`
        			for pn in $pn_list; do
        				pn=${pn%/}
        			
        				while [[ "${installed[$idx]}" < "$pn" && $idx -lt $ninstalled ]]; do
        					let idx++
        				done
        
        				if [[ "$pn" == "${installed[$idx]}" ]]; then
        					let idx++
        				else
        					echo $pn/ >>$RSYNC_EXCLUDES_FILE
        				fi
        			done
        		fi
        	done
	fi

        # sync portage tree
        eix-sync || emerge --sync
        [ 0 -ne $? ] && echo "Stage $STAGE: portage tree synchronization failed ;-( =======" && exit $STAGE

	# Update metadata cache
	in_list "$EGENCACHE" ${TRUE_LIST[@]} &&
	if [[ "git" == "$SYNC_TYPE" ]]; then
		echo "---------- Updating metadata cache for Git portage tree ----------"
		egencache --repo=gentoo --update --jobs=$((`grep "^processor" /proc/cpuinfo | wc -l`+1))
        	[ 0 -ne $? ] && echo "Stage $STAGE: Metadata update failed ;-( =======" && exit $STAGE
        fi

        # clear exclude list
        if [ "rsync" == "$SYNC_TYPE" ]; then
		echo -n > /etc/portage/rsync.excludes
        	[ 0 -ne $? ] && echo "Stage $STAGE: failed to clear /etc/portage/rsync.excludes ;-( =======" && exit $STAGE
	fi

        # eix update
        if [ `which eix-update 2>/dev/null` ]; then
                eix-update
                [ 0 -ne $? ] && echo "Stage $STAGE: eix-update failed ;-( =======" && exit $STAGE
        fi

        # eix-remote update
        if [ `which eix-remote 2>/dev/null` ]; then
                eix-remote update
                [ 0 -ne $? ] && echo "Stage $STAGE: eix-remote update failed ;-( =======" && exit $STAGE
        fi

        # layman syncronization
        if [ `which layman 2>/dev/null` ]; then
                layman -S
                [ 0 -ne $? ] && echo "Stage $STAGE: layman synchronization failed ;-( =======" && exit $STAGE
        fi

        # remind to upgrade Xorg input drivers
        tmp=`qlist -IC x11-base/xorg-server`
        if [ "" != "$tmp" ]; then
                if [ "0" -ne "`emerge -uNp x11-base/xorg-server 2>&1 | grep '^\[' | wc -l`" ]; then
                        touch /etc/portage/need_upgrade_xorg_input_drivers
                        [ 0 -ne $? ] && echo "Stage $STAGE: cann't touch /etc/portage/need_upgrade_xorg_input_drivers ;-( =======" && exit $STAGE
                fi
        fi

        let STAGE++
fi

# Stage 2: upgrading portage package
if [ 2 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: upgrading portage package ======="
        emerge -uq1v portage
        [ 0 -ne $? ] && echo "Stage $STAGE: portage package upgrading failed ;-( =======" && exit $STAGE

        let STAGE++
fi

# Stage 3: disable prelink
if [ 3 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: disable prelink ======="
        if [ `which prelink 2>/dev/null` ]; then
                prelink -ua 2>/dev/null
                [ 0 -ne $? ] && echo "Stage $STAGE: prelink disabling failed ;-( =======" && exit $STAGE
        fi

        let STAGE++
fi

# Stage 4: Test for necessity to upgrade toolchain packages
if [ 4 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Test for necessity to upgrade toolchain packages ======="
        cur_gcc_ver=`qlist -ICve sys-devel/gcc | sed 's~.*/gcc-~~'`
        new_gcc_ver=`emerge -uNp sys-devel/gcc | grep '^\[' | sed 's~.*/gcc-~~ ; s~\ .*~~'`
        if [[ "" != "$new_gcc_ver" && "`echo $cur_gcc_ver | sed 's~\([0-9]*\.[0-9]*\).*~\1~'`" != "`echo $new_gcc_ver | sed 's~\([0-9]*\.[0-9]*\).*~\1~'`" ]]; then
                touch /etc/portage/need_toolchain_rebuild
        else
                if [ "`echo $cur_gcc_ver | sed 's~[0-9]*\.[0-9]*\.\([0-9]*\).*~\1~'`" != "`echo $cur_gcc_ver | sed 's~[0-9]*\.[0-9]*\.\([0-9]*\).*~\1~'`" ]; then
                        touch /etc/portage/need_libtool_rebuild
                fi
                if [ 0 -ne "`emerge -uNp sys-kernel/linux-headers 2>&1 | grep '^\[' | wc -l`" ]; then
                        touch /etc/portage/need_glibc_rebuild
                fi
        fi

        let STAGE++
fi

# Stage 5: Toolchain packages rebuild and possibly 1'th full toolchain rebuild
if [ 5 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: 1'th toolchain build ======="

        if [ -f /etc/portage/need_libtool_rebuild ]; then
                emerge -1vq sys-devel/libtool
                rm /etc/portage/need_libtool_rebuild
                [ 0 -ne $? ] && echo "Stage $STAGE: cann't remove /etc/portage/need_libtool_rebuild ;-( =======" && exit $STAGE
        fi
        if [ -f /etc/portage/need_glibc_rebuild ]; then
                emerge -1vq sys-libs/glibc
                rm /etc/portage/need_glibc_rebuild
                [ 0 -ne $? ] && echo "Stage $STAGE: cann't remove /etc/portage/need_glibc_rebuild ;-( =======" && exit $STAGE
        fi
        if [ -f /etc/portage/need_toolchain_rebuild ]; then
                # remove old binary packages
                pkgdir=$(portageq pkgdir)
                rm -rf $pkgdir
                install -d -o portage -g portage -m775 $pkgdir

                # first toolchain build
                emerge -1vq sys-kernel/linux-headers sys-libs/glibc sys-devel/binutils \
                          sys-devel/gcc-config sys-devel/gcc sys-devel/binutils-config
                [ 0 -ne $? ] && echo "Stage $STAGE: 1'th toolchain build failed ;-( =======" && exit $STAGE
                rm /etc/portage/need_toolchain_rebuild
                [ 0 -ne $? ] && echo "Stage $STAGE: cann't remove /etc/portage/need_toolchain_rebuild ;-( =======" && exit $STAGE

        	let STAGE++

        # skip next toolchain upgrade stages
        else
                let STAGE=10
        fi
fi

# Stage 6: switching gcc and binutils
if [ 6 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: switching gcc and binutils ======="
        gcc_regex=`gcc-config -c | sed 's~[0-9]*\.[0-9]*\.[0-9]*~[0-9]*\.[0-9]*\.[0-9]*~'`
        [ "" == "$gcc_regex" ] && echo "Stage $STAGE: failed to build gcc_regex ;-( =======" && exit $STAGE
        binutils_regex=`binutils-config -c | sed 's~[0-9]*\.[0-9]*\.[0-9]*~[0-9]*\.[0-9]*\.[0-9]*~'`
        [ "" == "$binutils_regex" ] && echo "Stage $STAGE: failed to build binutils_regex ;-( =======" && exit $STAGE
        new_gcc=`gcc-config -l | cut -d" " -f3 | grep ^$gcc_regex$ | sort -V | tail -n1`
        [ "" == "$gcc_regex" ] && echo "Stage $STAGE: failed to find new_gcc ;-( =======" && exit $STAGE
        new_binutils=`binutils-config -l | cut -d" " -f3 | grep ^$binutils_regex$ | sort -V | tail -n1`
        [ "" == "$binutils_regex" ] && echo "Stage $STAGE: failed to find new_binutils ;-( =======" && exit $STAGE
        gcc-config $new_gcc
        [ 0 -ne $? ] && echo "Stage $STAGE: failed to switch gcc to $new_gcc ;-( =======" && exit $STAGE
        binutils-config $new_binutils
        [ 0 -ne $? ] && echo "Stage $STAGE: failed to switch binutils to $new_binutils ;-( =======" && exit $STAGE

        let STAGE++
fi

# Stage 7: 2'nd toolchain build
if [ 7 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: 2'nd toolchain build ======="
        source /etc/profile
        emerge -1bvq sys-libs/glibc sys-devel/binutils sys-devel/gcc sys-apps/portage
        [ 0 -ne $? ] && echo "Stage $STAGE: 2'nd toolchain build failed ;-( ========" && exit $STAGE

        let STAGE++
fi

# Stage 8: rebuild @system
if [ 8 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: rebuild @system ======="
        source /etc/profile
        emerge -1bkevq @system
        [ 0 -ne $? ] && echo "Stage $STAGE: @system rebuild failed ;-( =======" && exit $STAGE

        let STAGE++
fi

# Stage 9: rebuild @world
if [ 9 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: rebuild @world ======="
        source /etc/profile
        emerge -1bkevq @world
        [ 0 -ne $? ] && echo "Stage $STAGE: @world rebuild failed ;-( =======" && exit $STAGE

        let STAGE++
fi

# Stage 10: @system upgrade
if [ 10 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: @system upgrade ======="

        echo 'Test and remember if we should run python-updater after @system upgrade'
        if [ 0 -ne `emerge -uNp dev-lang/python 2>&1 | grep '^\[' | wc -l` ]; then
	        touch /etc/portage/need_upgrade_python
        fi

        echo 'Looking for necessity to upgrade @system packages...'
        if [ `emerge -uDNp --with-bdeps=y @system 2>&1 | grep '^\[' | wc -l` != 0 ]; then
	        echo '------- Upgrading @system packages -------'
        	emerge -uDNqv --with-bdeps=y @system
                [ 0 -ne $? ] && echo "Stage $STAGE: @system upgrade failed ;-( =======" && exit $STAGE
        else
        	echo '------- No @system packages to upgrade! -------'
        fi

        let STAGE++
fi

# Stage 11: Python upgrade
if [ 11 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Python upgrade ======="
	available_python_list=`eselect python list | cut -d" " -f6 | grep -v ^$ | sort -rV`
	[ "" == "$available_python_list" ] && echo "Stage $STAGE: empty available_python_list ;-( =======" && exit $STAGE

	let ndeps=0
	new_python=`echo $available_python_list | cut -d" " -f1`

	for p in $available_python_list ;  do
		pkgname=`echo $p | sed 's~^python~python-~'`
		let tmp=`equery d =dev-lang/$pkgname | cut -d" " -f1 | wc -l`
		[ $tmp -gt $ndeps ] && new_python=$p && let ndeps=$tmp
	done

	old_python=`eselect python show 2>/dev/null`

	if [[ "$old_python" != "$new_python" || -f /etc/portage/need_upgrade_python ]]; then
		echo "Running python-updater..."
		touch /etc/portage/need_upgrade_python
		[ 0 != $? ] && echo "Stage $STAGE: cann't touch /etc/portage/need_upgrade_xorg_input_drivers ;-( =======" && exit $STAGE
		eselect python set $new_python
		[ 0 != $? ] && echo "Stage $STAGE: cann't switch to another python version ;-( =======" && exit $STAGE
		python-updater
		[ 0 != $? ] && echo "Stage $STAGE: python-updater failed ;-( =======" && exit $STAGE
		rm /etc/portage/need_upgrade_python
		[ 0 != $? ] && echo "Stage $STAGE: cann't remove /etc/portage/need_upgrade_xorg_input_drivers ;-( =======" && exit $STAGE
	else
		echo "------- Not need to upgrade python -------"
	fi

        let STAGE++
fi


# Stage 12: @world upgrade
if [ 12 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: @world upgrade ======="
        echo 'Looking for necessity to upgrade @world packages...'
        if [ `emerge -uDNp --with-bdeps=y @world 2>&1 | grep '^\[' | wc -l` != 0 ]; then
	        echo '------- Upgrading @world packages -------'
        	emerge -uDNqv --with-bdeps=y @world
                [ 0 -ne $? ] && echo "Stage $STAGE: @world upgrade failed ;-( =======" && exit $STAGE
        	echo '------- Scanning for missed shared libraries -------'
        else
        	echo '------- No @world packages to upgrade! -------'
        fi

        let STAGE++
fi

# Stage 13: Xorg server upgrades
if [ 13 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Xorg server upgrades ======="
        if [ -f /etc/portage/need_upgrade_xorg_input_drivers ]; then
                echo '------- Upgrading Xorg input drivers -------'
                xorg_packages=`qlist -IC xf86-input xorg-drivers xf86-input-evdev xf86-input-wacom`
	        if [ "" != "$xorg_packages" ]; then
                        emerge -1qv $xorg_packages
                        [ 0 -ne $? ] && echo "Stage $STAGE: Xorg input drivers upgrade failed ;-( =======" && exit $STAGE
                        rm /etc/portage/need_upgrade_xorg_input_drivers
                        [ 0 -ne $? ] && echo "Stage $STAGE: cann't remove /etc/portage/need_upgrade_xorg_input_drivers ;-( =======" && exit $STAGE
                fi
        else
        	echo '------- No Xorg server upgrades! -------'
        fi

        let STAGE++
fi

# Stage 14: Cleaning
if [ 14 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Cleaning ======="
        emerge -c
        [ 0 -ne $? ] && echo "Stage $STAGE: emerge -c failed ;-( =======" && exit $STAGE
        if [ `which localepurge 2>/dev/null` ]; then
                localepurge &>/dev/null
                [ 0 -ne $? ] && echo "Stage $STAGE: localepurge failed ;-( =======" && exit $STAGE
        fi
        if [ `which eclean 2>/dev/null` ]; then
                eclean packages
                [ 0 -ne $? ] && echo "Stage $STAGE: eclean packages failed ;-( =======" && exit $STAGE
                eclean distfiles
                [ 0 -ne $? ] && echo "Stage $STAGE: eclean distfiles failed ;-( =======" && exit $STAGE
        fi
        rm -rf /var/tmp/portage/*
        [ 0 -ne $? ] && echo "Stage $STAGE: rm -rf /var/tmp/portage/* failed ;-( =======" && exit $STAGE

        let STAGE++
fi

# Stage 15: Scan for missed shared libraries
if [ 15 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Scan for old versions of shared libraries ======="
        emerge -1qv @preserved-rebuild
        [ 0 -ne $? ] && echo "Stage $STAGE: emerge -1qv @preserved-rebuild failed ;-( =======" && exit $STAGE

        let STAGE++
fi

# Stage 16: Scan for vulnearable packages and try to fix them
if [ 16 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Scan for vulnearable packages ======="
        if [ `which glsa-check 2>/dev/null` ]; then
                glsa-check -f affected
                # [ 0 -ne $? ] && echo "Stage $STAGE: glsa-check fix failed ;-( =======" && exit $STAGE
        fi

        let STAGE++
fi

# Stage 17: Prelink libraries
if [ 17 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Prelink libraries ======="
        if [ `which prelink 2>/dev/null` ]; then
                prelink -avfmR
                [ 0 -ne $? ] && echo "Stage $STAGE: prelink -avfmR failed ;-( =======" && exit $STAGE
        fi

        let STAGE++
fi

# Stage 18: Upgrade kernel
if [ 18 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Upgrade kernel ======="
	kernel-getlast.sh
        [ 0 -ne $? ] && echo "Stage $STAGE: kernel-getlast.sh failed ;-( =======" && exit $STAGE

	let STAGE++
fi

# Stage 19: Update config files
if [ 19 -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Update config files ======="
        etc-update
        [ 0 -ne $? ] && echo "Stage $STAGE: etc-update failed ;-( =======" && exit $STAGE

        let STAGE++
fi

exit 0