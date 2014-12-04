#!/usr/bin/env bash

COMPLETED_BYTES=`expr $TAR_CHECKPOINT "*" $TAR_BLOCKING_FACTOR "*" 512`
PERCENT_COMPLETE=`echo "scale=1; $COMPLETED_BYTES * 100 / $ARCHIVE_SIZE_BYTES" | bc`

OPERATION_NAME="Unknown"

case $TAR_SUBCOMMAND in
	"-c")
	OPERATION_NAME="Creating"
	;;
	"-x")
	OPERATION_NAME="Extracting"
	;;
	*)
esac

CHECKPOINT_MESSAGE="$OPERATION_NAME $TAR_ARCHIVE, Operation running, ${PERCENT_COMPLETE}% complete."

echo "***** TAR checkpoint $TAR_CHECKPOINT"
aws sns publish --topic-arn $STATUS_UPDATE_ARN --message "$CHECKPOINT_MESSAGE"
