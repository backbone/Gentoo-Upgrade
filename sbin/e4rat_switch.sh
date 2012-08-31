#!/bin/bash

if [[ `which e4rat-realloc 2>/dev/null` && `grep 'init=/sbin/e4rat-' /boot/grub/grub.conf` ]]; then
  echo "e4rat package and e4rat init record in grub.conf found ;-)"
else
  echo "Either e4rat package or e4rat record in grub.conf not found, exiting..."
  exit 0
fi

case $1 in
  collect)
    echo "Setting up e4rat for collecting data"
    echo "remounting /boot -> rw"
    mount -o remount,rw /boot && \
    sed -i "s~init=/sbin/e4rat-[a-z]*~init=/sbin/e4rat-collect~g" \
      /boot/grub/grub.conf && \
    echo "remounting /boot -> ro" && \
    mount -o remount,ro /boot && \
    echo -e "#/bin/bash\n\n(/usr/sbin/e4rat_finalize.sh && rm -f /etc/local.d/e4rat_finalize.start)&\n" \
      > /etc/local.d/e4rat_finalize.start && \
    chmod 755 /etc/local.d/e4rat_finalize.start
    [ 0 -ne $? ] && echo "e4rat_switch.sh $1 failed" && exit -1
    ;;
  preload)
    echo "Setting up e4rat for preload system files"
    echo "remounting /boot -> rw"
    mount -o remount,rw /boot && \
    sed -i "s~init=/sbin/e4rat-[a-z]*~init=/sbin/e4rat-preload~g" \
      /boot/grub/grub.conf && \
    echo "remounting /boot -> ro" && \
    mount -o remount,ro /boot
    [ 0 -ne $? ] && echo "e4rat_switch.sh $1 failed" && exit -1
    ;;
  *)
    echo "Usage: e4rat_switch.sh {collect|preload}"
    exit -1
    ;;
esac

exit 0
