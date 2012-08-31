#!/bin/bash

let timeout=0`grep --color=NO '^[ \t]*timeout' /etc/e4rat.conf | head -n1 | awk '{print $2}'`
[ 0 -eq $timeout ] && timeout=120

startup_log_file=`grep --color=NO '^[ \t]*\<startup_log_file\>' /etc/e4rat.conf | awk '{print $2}'`
[[ "" == "$startup_log_file" ]] && startup_log_file=/var/lib/e4rat/startup.log

sleep $timeout

e4rat-collect -k
pkill e4rat-collect

e4rat-realloc $startup_log_file

e4rat_switch.sh preload
