#!/bin/bash

DEST_FILE=`echo $@ | sed 's~.* ~~g'`
/usr/bin/getdelta.sh "$@"
if [ ! -f "$DEST_FILE" ]; then
        echo "======= FULL DOWNLOAD... ======"
        echo "======= PARAMS: $@ ======"
        /usr/bin/wget -t1 --passive-ftp $@
fi

exit 0

