#!/bin/bash

echo "======= PARAMS: $@ ======"
URL=`echo $@ | awk '{print $1}'`
DEST_FILE=`echo $@ | awk '{print $3}'`

/usr/bin/getdelta.sh $URL

if [ -f "$DEST_FILE" ]; then
	exit 0
else
	echo "======= PARAMS: $@ ======"
	URL_FNAME=${URL##*/}
	DEST_FILE_DIR=${DEST_FILE%/*}
	if [[ ! -z "$URL_FNAME" && ! -z "${DEST_FILE##*/}"
	   && ! -z "$DEST_FILE_DIR" && -f ${DEST_FILE%/*}/$URL_FNAME ]]; then
		echo --- MOVING $URL_FNAME TO ${DEST_FILE##*/} ---
		mv -f $DEST_FILE_DIR/$URL_FNAME $DEST_FILE
		exit $?
	else
		echo "======= FULL DOWNLOAD... ======"
		/usr/bin/wget -t1 --passive-ftp $@
		exit $?
	fi
fi

exit -1

