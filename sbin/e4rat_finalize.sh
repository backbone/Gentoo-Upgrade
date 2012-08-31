#!/bin/bash

let timeout=0`grep --color=NO '^[ \t]*timeout' /etc/e4rat.conf | head -n1 | sed 's~[^0-9]\+\([0-9]\+\).*~\1~'`

sleep $timeout

e4rat-collect -k
pkill e4rat-collect

e4rat-realloc /var/lib/e4rat/startup.log

e4rat_switch.sh preload
