#!/usr/bin/env bash

#awstar.sh

usage() {
    echo "Usage: " `basename $0` JOB_NAME SOURCE_DIR "[...]"
}

awstar_init.sh
source ~/.awstar

RUNDATE=`date "+%Y%m%d_%H%M"`
LOGFILE="${RUNDATE}_tar.log"
STATUS_UPDATE_ARN=$AWSTAR_UPDATE_ARN
VOLUME_SIZE=250M
INFO_SCRIPT_COMMAN=$(which awstar_autoload.sh)
WRITE_VOLUME_COMMAND=$(which awstar_write_volume.sh)
CHECKPOINT_COMMAND=$(which awstar_checkpoint.sh)

JOB_NAME=$1
shift ## remaining arguments are directories

ARCHIVE_NAME=$JOB_NAME-$RUNDATE
S3_BUCKET_NAME=$AWSTAR_S3_BUCKET_PREFIX-arch-$(date +"%Y")
ARCHIVE_BASE_PREFIX_S3URL=s3://$S3_BUCKET_NAME/$ARCHIVE_NAME

GIGABYTE=$(expr 1024 "*" 1024 "*" 1024)
RECORD_SIZE_BYTES=$(expr 20 "*" 512)
CHECKPOINT_BYTES=$GIGABYTE
CHECKPOINT_FREQ=$( echo "$CHECKPOINT_BYTES / $RECORD_SIZE_BYTES" | bc ) 

PATHS_TO_BACKUP=$1

cat <<MSG
+-----------------------------------------------------------------------------+
|                               Create Archive                                |
+-----------------------------------------------------------------------------+
|Archive Base Name : $(printf %-57s "$JOB_NAME")|
|Archive Name      : $(printf %-57s "$ARCHIVE_NAME")|   
|Save Location     : $(printf %-57s "$ARCHIVE_BASE_PREFIX_S3URL")|
|Source Path       : $(printf %-57s "$PATHS_TO_BACKUP")|
|Checkpoints       : $(printf %-57s "Every $CHECKPOINT_BYTES bytes")|
+-----------------------------------------------------------------------------+
MSG

ARCHIVE_SIZE_BYTES=`du -c --bytes "$PATHS_TO_BACKUP" | tail -n 1 | cut -f1`
START_MESSAGE="Archive job $JOB_NAME started, $ARCHIVE_SIZE_BYTES bytes to archive."

if [ -z $STY ]; then
	aws sns publish --topic-arn $STATUS_UPDATE_ARN --message "$START_MESSAGE" 
else 
	aws sns publish --topic-arn $STATUS_UPDATE_ARN --message "$START_MESSAGE. Screen session $STY"
fi

cat <<MSG
|Total to archive  : $(printf %-57s "$ARCHIVE_SIZE_BYTES bytes")|
+-----------------------------------------------------------------------------+
MSG

if aws s3 ls s3://$S3_BUCKET_NAME; then
	echo "The bucket $S3_BUCKET_NAME already exists!"
else

	echo "Creating bucket $S3_BUCKET_NAME..."
	aws s3 mb s3://$S3_BUCKET_NAME

	# preapre bucket
LIFECYCLE_CONFIG=`cat <<-JSON
{
  "Rules": [
    {
      "ID": "To_Glacier_In_30_Days",
      "Prefix": "",
      "Status": "Enabled",
      "Transition": {
        "Days": 30,
        "StorageClass": "GLACIER"
      }
    }
  ]
}
JSON`

		if [ $? != 0 ]; then
		echo "Failed to create bucket $S3_BUCKET_NAME with error $?. Exiting..."

	fi
	echo "Creating Glacier lifecycle rule..."
	aws s3api put-bucket-lifecycle --bucket $S3_BUCKET_NAME --lifecycle-configuration \
"$LIFECYCLE_CONFIG"

fi #aws s3 ls

echo "Creating tree file..."

tree "$PATHS_TO_BACKUP" > $ARCHIVE_NAME.tree.txt

aws s3 mv $ARCHIVE_NAME.tree.txt $ARCHIVE_BASE_PREFIX_S3URL/$ARCHIVE_NAME.tree.txt

# prepare first volume

echo "Creating volume pipeline..."
FIRST_VOL=$ARCHIVE_NAME.001.tar

export ARCHIVE_BASE_PREFIX_S3URL 
export STATUS_UPDATE_ARN
export ARCHIVE_SIZE_BYTES
export kmg

echo "Running tar..."
tar --create \
--info-script=$INFO_SCRIPT_COMMAND \
--multi-volume --tape-length=$VOLUME_SIZE \
--volno-file=_tar_volnum \
--exclude "WaveCache.wfm" \
--checkpoint=$CHECKPOINT_FREQ \
--checkpoint-action=exec=$CHECKPOINT_COMMAND \
--file "$FIRST_VOL" "$PATHS_TO_BACKUP" | tee $LOGFILE

# Upload last file
echo Writing final volume...
LAST_VOL=$(printf $ARCHIVE_NAME.%03i.tar $(cat _tar_volnum))

$WRITE_VOLUME_COMMAND $LAST_VOL $ARCHIVE_BASE_PREFIX_S3URL 

aws s3 mv $LOGFILE $ARCHIVE_BASE_PREFIX_S3URL/$LOGFILE

aws sns publish --topic-arn $STATUS_UPDATE_ARN --message "Archive $JOB_NAME completed. $(cat _tar_volnum) volumes written"

rm _tar_volnum
