#!/bin/bash

STAGE=0
NICE_CMD="nice -n 19 ionice -c2"
let QUIET=0

[ -f /etc/make.conf ] && source /etc/make.conf
[ -f /etc/portage/make.conf ] && source /etc/portage/make.conf
[ -f /etc/gentoo-upgrade.conf ] && source /etc/gentoo-upgrade.conf

# available parameters
eval set -- "`getopt -o hs:q --long help,stage:,quiet -- \"$@\"`"

while true ; do
        case "$1" in
                -h|--help)
                        echo "Usage: upgrade-gentoo.sh [keys]..."
                        echo "Keys:"
                        echo -e "-h, --help\t\t\tShow this help and exit."
                        echo -e "-s [STAGE], --stage [STAGE]\tGo to STAGE upgrade level."
                        echo -e "-q, --quiet\t\t\tMake kernel configuration non-interactive."
                        echo
                        echo -e "This program works on any GNU/Linux with GNU Baurne's shell"
                        echo -e "Report bugs to <mecareful@gmail.com>"
                        exit 0
                        ;;
		-s|--stage) STAGE=$2 ; shift 2 ;;
		-q|--quiet) let QUIET=1 ; shift ;;
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
STAGE_CNT=0

# remounting file systems ro->rw
if [ $STAGE_CNT -eq $STAGE ]; then
	echo "======= STAGE $STAGE: remounting file systems ro->rw ======="
	for fs in $RW_REMOUNT; do
		echo "remounting $fs -> rw"
		mount -o remount,rw $fs
		[ 0 -ne $? ] && echo "Stage $STAGE: mount -o remount,rw $fs failed ;-( =======" && exit $STAGE
	done

	let STAGE++
fi
let STAGE_CNT++

# Pull portage config changes
if [ $STAGE_CNT -eq $STAGE ]; then
	if [ -d /etc/portage/.git ]; then
		echo "======= STAGE $STAGE: pull portage config changes ======="
		cd /etc/portage && git pull origin `git rev-parse --abbrev-ref HEAD`
		[ 0 -ne $? ] && echo "Stage $STAGE: cd /etc/portage && git pull origin `git rev-parse --abbrev-ref HEAD` failed ;-( =======" && exit $STAGE
	fi

	let STAGE++
fi
let STAGE_CNT++

# Update gentoo-upgrade script
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Updating gentoo-upgrade script ======="
        if [ `which smart-live-rebuild 2>/dev/null` ]; then
                $NICE_CMD smart-live-rebuild app-admin/gentoo-upgrade
                [ 0 -ne $? ] && echo "Stage $STAGE: Updating gentoo-upgrade script failed ;-( =======" && exit $STAGE
        fi

        exec $0 -s $((STAGE+1))

        echo "Stage $STAGE: Bash translator in unreachable code ;-(" && exit $STAGE

	let STAGE++
fi
let STAGE_CNT++

# sync portage tree
if [ $STAGE_CNT -eq $STAGE ]; then
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

        # layman syncronization
        if [ `which layman 2>/dev/null` ]; then
                $NICE_CMD layman -S
                [ 0 -ne $? ] && echo "Stage $STAGE: layman synchronization failed ;-( =======" && exit $STAGE
        fi

        # sync portage tree
        $NICE_CMD eix-sync || $NICE_CMD emerge --sync
        [ 0 -ne $? ] && echo "Stage $STAGE: portage tree synchronization failed ;-( =======" && exit $STAGE

	# Update metadata cache
	in_list "$EGENCACHE" ${TRUE_LIST[@]} &&
	if [[ "git" == "$SYNC_TYPE" ]]; then
		echo "---------- Updating metadata cache for Git portage tree ----------"
		$NICE_CMD egencache --repo=gentoo --update --jobs=$((`getconf _NPROCESSORS_ONLN`+1))
        	[ 0 -ne $? ] && echo "Stage $STAGE: Metadata update failed ;-( =======" && exit $STAGE
        fi

        # clear exclude list
        if [ "rsync" == "$SYNC_TYPE" ]; then
		echo -n > /etc/portage/rsync.excludes
        	[ 0 -ne $? ] && echo "Stage $STAGE: failed to clear /etc/portage/rsync.excludes ;-( =======" && exit $STAGE
	fi

        # eix-remote update
        if [ `which eix-remote 2>/dev/null` ]; then
                $NICE_CMD eix-remote update
                [ 0 -ne $? ] && echo "Stage $STAGE: 1'st eix-remote update failed ;-( =======" && exit $STAGE
        fi

        # eix update
        if [ `which eix-update 2>/dev/null` ]; then
                $NICE_CMD eix-update
                [ 0 -ne $? ] && echo "Stage $STAGE: eix-update failed ;-( =======" && exit $STAGE
        fi

        # eix-remote update
        if [ `which eix-remote 2>/dev/null` ]; then
                $NICE_CMD eix-remote update
                [ 0 -ne $? ] && echo "Stage $STAGE: 2'nd eix-remote update failed ;-( =======" && exit $STAGE
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

	# recreate portage squashfs files
	if [[ -x /etc/init.d/squash_portage && "" != "`mount | grep '^aufs' | grep $PORTDIR`" ]]; then
		/etc/init.d/squash_portage restart
		[ 0 -ne $? ] && echo "Stage $STAGE: cann't restart squash_portage ;-( =======" && exit $STAGE
	fi
fi
let STAGE_CNT++

# upgrading portage package
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: upgrading portage package ======="
        emerge -uq1v portage
        [ 0 -ne $? ] && echo "Stage $STAGE: portage package upgrading failed ;-( =======" && exit $STAGE

        let STAGE++
fi
let STAGE_CNT++

# disable prelink
#if [ $STAGE_CNT -eq $STAGE ]; then
#        echo "======= STAGE $STAGE: disable prelink ======="
#        if [ `which prelink 2>/dev/null` ]; then
#                $NICE_CMD prelink -ua 2>/dev/null
#                [ 0 -ne $? ] && echo "Stage $STAGE: prelink disabling failed ;-( =======" && exit $STAGE
#        fi
#
#        let STAGE++
#fi
#let STAGE_CNT++

# Test for necessity to upgrade toolchain packages
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Test for necessity to upgrade toolchain packages ======="
        cur_gcc_ver=`qlist -ICve sys-devel/gcc | sed 's~.*/gcc-~~'`
        new_gcc_ver=`emerge -uNp sys-devel/gcc | grep '^\[' | sed 's~.*/gcc-~~ ; s~\ .*~~'`
        if [[ "" != "$new_gcc_ver" && "`echo $cur_gcc_ver | sed 's~\([0-9]*\.[0-9]*\).*~\1~'`" != "`echo $new_gcc_ver | sed 's~\([0-9]*\.[0-9]*\).*~\1~'`" ]]; then
                touch /etc/portage/need_toolchain_rebuild
                touch /etc/portage/need_kernel_rebuild
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
let STAGE_CNT++

# Toolchain packages rebuild and possibly 1'th full toolchain rebuild
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: 1'th toolchain build ======="

        if [ -f /etc/portage/need_libtool_rebuild ]; then
                emerge -1vq sys-devel/libtool
                rm /etc/portage/need_libtool_rebuild
                [ 0 -ne $? ] && echo "Stage $STAGE: cann't remove /etc/portage/need_libtool_rebuild ;-( =======" && exit $STAGE
        fi
        if [ -f /etc/portage/need_glibc_rebuild ]; then
                emerge -1vq sys-kernel/linux-headers sys-libs/glibc
                rm /etc/portage/need_glibc_rebuild
                [ 0 -ne $? ] && echo "Stage $STAGE: cann't remove /etc/portage/need_glibc_rebuild ;-( =======" && exit $STAGE
        fi
        if [ -f /etc/portage/need_toolchain_rebuild ]; then
                # remove old binary packages
                pkgdir=$(portageq pkgdir)
                rm -rf $pkgdir
                install -d -o portage -g portage -m775 $pkgdir

                # first toolchain build
                emerge -1uvq sys-kernel/linux-headers sys-libs/glibc sys-devel/binutils \
                          sys-devel/gcc-config sys-devel/gcc sys-devel/binutils-config sys-devel/libtool
                [ 0 -ne $? ] && echo "Stage $STAGE: 1'th toolchain build failed ;-( =======" && exit $STAGE
                rm /etc/portage/need_toolchain_rebuild
                [ 0 -ne $? ] && echo "Stage $STAGE: cann't remove /etc/portage/need_toolchain_rebuild ;-( =======" && exit $STAGE

        	let STAGE++

        # skip next toolchain upgrade stages
        else
                let STAGE+=5
        fi
fi
let STAGE_CNT++

# switching gcc and binutils
if [ $STAGE_CNT -eq $STAGE ]; then
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
let STAGE_CNT++

# 2'nd toolchain build
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: 2'nd toolchain build ======="
        source /etc/profile
        emerge -1bv sys-libs/glibc sys-devel/binutils sys-devel/gcc sys-apps/portage
        [ 0 -ne $? ] && echo "Stage $STAGE: 2'nd toolchain build failed ;-( ========" && exit $STAGE

        let STAGE++
fi
let STAGE_CNT++

# rebuild @system
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: rebuild @system ======="
        source /etc/profile
        emerge -1bkev @system
        [ 0 -ne $? ] && echo "Stage $STAGE: @system rebuild failed ;-( =======" && exit $STAGE

        let STAGE++
fi
let STAGE_CNT++

# rebuild @world
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: rebuild @world ======="
        source /etc/profile
        emerge -1bkev @world
        [ 0 -ne $? ] && echo "Stage $STAGE: @world rebuild failed ;-( =======" && exit $STAGE

        let STAGE++
fi
let STAGE_CNT++

# @system upgrade
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: @system upgrade ======="

        echo 'Test and remember if we should run python-updater after @system upgrade'
        if [ 0 -ne `emerge -uNp dev-lang/python 2>&1 | grep '^\[' | wc -l` ]; then
	        touch /etc/portage/need_upgrade_python
        fi

        echo 'Test and remember if we should run perl-cleaner after @system upgrade'
        if [[ 0 -ne `qlist -IC dev-lang/perl | wc -l`
              && 0 -ne `emerge -uNp dev-lang/perl 2>&1 | grep '^\[' | wc -l` ]]; then
	        touch /etc/portage/need_upgrade_perl
        fi

        echo 'Test and remember if we should run haskell-updater after @system upgrade'
        if [[ 0 -ne `qlist -IC dev-lang/ghc | wc -l`
              &&  0 -ne `emerge -uNp dev-lang/ghc 2>&1 | grep '^\[' | wc -l` ]]; then
	        touch /etc/portage/need_upgrade_haskell
        fi

        echo '------- Upgrading @system packages -------'
        emerge -uDNv --with-bdeps=y @system
        [ 0 -ne $? ] && echo "Stage $STAGE: @system upgrade failed ;-( =======" && exit $STAGE

        let STAGE++
fi
let STAGE_CNT++

# Python upgrade
if [ $STAGE_CNT -eq $STAGE ]; then
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
		[ 0 != $? ] && echo "Stage $STAGE: cann't touch /etc/portage/need_upgrade_python ;-( =======" && exit $STAGE
		eselect python set $new_python
		[ 0 != $? ] && echo "Stage $STAGE: cann't switch to another python version ;-( =======" && exit $STAGE
		$NICE_CMD python-updater
		[ 0 != $? ] && echo "Stage $STAGE: python-updater failed ;-( =======" && exit $STAGE
		rm /etc/portage/need_upgrade_python
		[ 0 != $? ] && echo "Stage $STAGE: cann't remove /etc/portage/need_upgrade_python ;-( =======" && exit $STAGE
	else
		echo "------- Not need to upgrade python -------"
	fi

        let STAGE++
fi
let STAGE_CNT++

# Perl upgrade
if [ $STAGE_CNT -eq $STAGE ]; then
	echo "======= STAGE $STAGE: Perl upgrade ======="

	if [ -f /etc/portage/need_upgrade_perl ]; then
		echo "Running perl-cleaner..."
		$NICE_CMD perl-cleaner --all
		[ 0 != $? ] && echo "Stage $STAGE: perl-cleaner failed ;-( =======" && exit $STAGE
		rm /etc/portage/need_upgrade_perl
		[ 0 != $? ] && echo "Stage $STAGE: cann't remove /etc/portage/need_upgrade_perl ;-( =======" && exit $STAGE
	else
		echo "------- Not need to upgrade perl -------"
	fi

        let STAGE++
fi
let STAGE_CNT++

# Haskell upgrade
if [ $STAGE_CNT -eq $STAGE ]; then
	echo "======= STAGE $STAGE: Haskell upgrade ======="

	if [ -f /etc/portage/need_upgrade_haskell ]; then
		echo "Running haskell-updater..."
		$NICE_CMD haskell-updater --upgrade
		[ 0 != $? ] && echo "Stage $STAGE: haskell-updater --upgrade failed ;-( =======" && exit $STAGE
		rm /etc/portage/need_upgrade_haskell
		[ 0 != $? ] && echo "Stage $STAGE: cann't remove /etc/portage/need_upgrade_haskell ;-( =======" && exit $STAGE
	else
		echo "------- Not need to upgrade Haskell -------"
	fi

        let STAGE++
fi
let STAGE_CNT++

# @world upgrade
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: @world upgrade ======="
        echo 'Looking for necessity to upgrade @world packages...'
        emerge -uDNv @world
        [ 0 -ne $? ] && echo "Stage $STAGE: @world upgrade failed ;-( =======" && exit $STAGE

        let STAGE++
fi
let STAGE_CNT++

# Xorg server upgrades
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Xorg server upgrades ======="
        if [ -f /etc/portage/need_upgrade_xorg_input_drivers ]; then
                echo '------- Upgrading Xorg input drivers -------'
                emerge -1v @x11-module-rebuild `qlist -IC xf86-input xorg-drivers`
                [ 0 -ne $? ] && echo "Stage $STAGE: Xorg input drivers upgrade failed ;-( =======" && exit $STAGE
                rm /etc/portage/need_upgrade_xorg_input_drivers
                [ 0 -ne $? ] && echo "Stage $STAGE: cann't remove /etc/portage/need_upgrade_xorg_input_drivers ;-( =======" && exit $STAGE
        else
        	echo '------- No Xorg server upgrades! -------'
        fi

        let STAGE++
fi
let STAGE_CNT++

# Upgrading live packages
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Upgrading live packages ======="
        smart-live-rebuild
        [ 0 -ne $? ] && echo "Stage $STAGE: Upgrading live packages failed ;-( =======" && exit $STAGE

        let STAGE++
fi
let STAGE_CNT++

# Cleaning
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Cleaning ======="
        emerge -c
        [ 0 -ne $? ] && echo "Stage $STAGE: emerge -c failed ;-( =======" && exit $STAGE
        if [ `which localepurge 2>/dev/null` ]; then
                $NICE_CMD localepurge &>/dev/null
                [ 0 -ne $? ] && echo "Stage $STAGE: localepurge failed ;-( =======" && exit $STAGE
        fi
        if [ `which eclean 2>/dev/null` ]; then
                $NICE_CMD eclean -d packages
                [ 0 -ne $? ] && echo "Stage $STAGE: eclean -d packages failed ;-( =======" && exit $STAGE

                in_list "$ECLEAN_DISTFILES" ${TRUE_LIST[@]}
                if [ 0 -eq $? ]; then
                        $NICE_CMD eclean -d distfiles
                        [ 0 -ne $? ] && echo "Stage $STAGE: eclean -d distfiles failed ;-( =======" && exit $STAGE
                fi
        fi
        [ -z "${PORTAGE_TMPDIR}" ] && PORTAGE_TMPDIR=/var/tmp
        rm -rf "${PORTAGE_TMPDIR}"/portage/*
        [ 0 -ne $? ] && echo "Stage $STAGE: rm -rf "${PORTAGE_TMPDIR}"/portage/* failed ;-( =======" && exit $STAGE

        let STAGE++
fi
let STAGE_CNT++

# Scan for missed shared libraries
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Scan for old versions of shared libraries ======="
        emerge -1v @preserved-rebuild
        [ 0 -ne $? ] && echo "Stage $STAGE: emerge -1v @preserved-rebuild failed ;-( =======" && exit $STAGE

        let STAGE++
fi
let STAGE_CNT++

# Scan for vulnearable packages and try to fix them
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Scan for vulnearable packages ======="
        if [ `which glsa-check 2>/dev/null` ]; then
                $NICE_CMD glsa-check -f affected
                # [ 0 -ne $? ] && echo "Stage $STAGE: glsa-check fix failed ;-( =======" && exit $STAGE
        fi

        emerge -1pv @security

        let STAGE++
fi
let STAGE_CNT++

# Prelink libraries
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Prelink libraries ======="
        if [ `which prelink 2>/dev/null` ]; then
                $NICE_CMD prelink -avfmqR
                [ 0 -ne $? ] && echo "Stage $STAGE: prelink -avfmqR failed ;-( =======" && exit $STAGE
        fi

        let STAGE++
fi
let STAGE_CNT++

# Upgrade kernel
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Upgrade kernel ======="

        [ 1 -eq $QUIET ] && KERNEL_GETLAST_OPTS="$KERNEL_GETLAST_OPTS --quiet"

        if [ -f /etc/portage/need_kernel_rebuild ]; then
                kernel-getlast.sh --force-rebuild --mrproper $KERNEL_GETLAST_OPTS
                [ 0 -ne $? ] && echo "Stage $STAGE: kernel-getlast.sh --force-rebuild $KERNEL_GETLAST_OPTS failed ;-( =======" && exit $STAGE
                rm /etc/portage/need_kernel_rebuild
                [ 0 -ne $? ] && echo "Stage $STAGE: cann't remove /etc/portage/need_kernel_rebuild ;-( =======" && exit $STAGE
        else
                kernel-getlast.sh $KERNEL_GETLAST_OPTS
                [ 0 -ne $? ] && echo "Stage $STAGE: kernel-getlast.sh $KERNEL_GETLAST_OPTS failed ;-( =======" && exit $STAGE
        fi

	let STAGE++
fi
let STAGE_CNT++

# Update config files
if [ $STAGE_CNT -eq $STAGE ]; then
        echo "======= STAGE $STAGE: Update config files ======="
        etc-update
        [ 0 -ne $? ] && echo "Stage $STAGE: etc-update failed ;-( =======" && exit $STAGE

        let STAGE++
fi
let STAGE_CNT++

# remounting file systems rw->ro
if [ $STAGE_CNT -eq $STAGE ]; then
	echo "======= STAGE $STAGE: remounting file systems rw->ro ======="
	for fs in $RO_REMOUNT; do
		echo "remounting $fs -> ro"
		mount -o remount,ro -force $fs
	        [ 0 -ne $? ] && echo "Stage $STAGE: mount -o remount,ro -force $fs failed ;-( =======" && exit $STAGE
	done

	let STAGE++
fi
let STAGE_CNT++

# Enabling e4rat data collection
if [ $STAGE_CNT -eq $STAGE ]; then
	echo "======= STAGE $STAGE: Enabling e4rat data collection ======="
	e4rat_switch.sh collect
	[ 0 -ne $? ] && echo "Stage $STAGE: Enabling e4rat data collection failed ;-( =======" && exit $STAGE

	let STAGE++
fi
let STAGE_CNT++

# Collect data for file/package database
if [ $STAGE_CNT -eq $STAGE ]; then
	echo "======= STAGE $STAGE: Collect data for file/package database ======="
        if [ `which pfl 2>/dev/null` ]; then
		pfl
		[ 0 -ne $? ] && echo "Stage $STAGE: Collect data for file/package database failed ;-( =======" && exit $STAGE
        else
		echo "app-portage/pfl is not installed ;-("
        fi
fi
let STAGE_CNT++

exit 0
