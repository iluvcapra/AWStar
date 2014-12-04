#!/bin/bash
RUNDATE=`date "+%Y%m%d_%H%M"`
LOGFILE="${RUNDATE}_dar.log"
STATUS_UPDATE_ARN="arn:aws:sns:us-east-1:826181281546:jamiehardt_internal_notifications"

DEFAULT_SLICE_SIZE=250M

log() {
    echo "[`date "+%Y-%m-%d %H:%M:%S"`] $*" >> "$LOGFILE" 
}

logstdin() {
    	while read line; do
		log $line
	done
}

die() {
 status=$1 
 shift
 log "FATAL: $*"
 if [ -n $STATUS_UPDATE_ARN ]; then
 	aws sns publish --topic-arn $STATUS_UPDATE_ARN --message "FATAL: $*"
 fi
 exit $status
}


verifyTool() {
	if [ -z `which $1` ]; then
	die 1 "$1 is not present on the system"
	exit 127
	fi
}

verifyTool dar
verifyTool aws

EC2_INSTANCE_ID=`ec2metadata --instance-id`
test -n "$EC2_INSTANCE_ID" || die 'cannot obtain instance-id'
EC2_AVAIL_ZONE=`ec2metadata --availability-zone`
test -n "$EC2_AVAIL_ZONE" || die 'cannot obtain availability-zone'
EC2_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed -e 's:\([0-9][0-9]*\)[a-z]*\$:\\1:'`"

echo "Archive Path to S3 with DAR"
echo "==========================="
read -e -p "Source Path: " SOURCE_DIR
read -e -p "Archive Basename: " ARCHIVE_BASENAME
read -e -p "To Target S3 Bucket: " TARGET_BUCKET

read -e -p "Slice Size [$DEFAULT_SLICE_SIZE]: " SLICE_SIZE

echo "Action on EC2 Instance $EC2_INSTANCE_ID upon completion"
select ON_COMPLETION in "TERMINATE" "STOP" "NOTHING"; do
  break
done

echo ""

echo "Getting source path size..."
SOURCE_SIZE=`du -s -h "$SOURCE_DIR" | cut -f1`
echo ""

echo "Ready to begin archiving..."
select DO_RUN in "START" "CANCEL"; do
  if [ $DO_RUN = "CANCEL" ]; then
    echo "Cancelling."
    die 0 "User cancelled."
  fi
  break
done

log "User has started archiving."

if [ -n $STY ]; then
	log "Running in a screen session. Name: $STY"
	aws sns publish --topic-arn $STATUS_UPDATE_ARN --message "($ARCHIVE_BASENAME) Starting archive. screen session: $STY"
fi

log "%%%%%%%%%%%% JOB DETAILS %%%%%%%%%%%%%%%%%%"
log "%%  EC2 Instance ID:     " $EC2_INSTANCE_ID
log "%%  EC2 Region:          " $EC2_REGION
log "%%  Source path:         " ${SOURCE_DIR:-$DEFAULT_SLICE_SIZE}
log "%%  Archive Basename:    " $ARCHIVE_BASENAME
log "%%  Target Bucket:       " $TARGET_BUCKET
log "%%  Slice Size:          " $SLICE_SIZE
log "%%  Status Update ARN:   " $STATUS_UPDATE_ARN
log "%%  Completion action:   " $ON_COMPLETION

WORKING_DIR=dar_`uuidgen`

mkdir "$WORKING_DIR" || die "could not create working directory $WORKING_DIR"

aws s3 mb s3://$TARGET_BUCKET 2>&1 | logstdin || \
	die "could not create S3 bucket"


dar -c "$WORKING_DIR/$ARCHIVE_BASENAME" \
 -s ${SLICE_SIZE:-$DEFAULT_SLICE_SIZE} -R "$SOURCE_DIR" \
 -X "WaveCache.wfm" \
 -v \
 -z -Z "*.zip" -Z "*.gz" -Z "*.mov" -Z "*.mp*" -Z "*.m4[avp]" \
 -E "aws s3 cp %p/%b.%N.%e s3://$TARGET_BUCKET/%b.%N.%e 2>&1 | logstdin" \
 -E "rm %p/%b.%N.%e" 2>&1 | logstdin \
 || die $? "dar failed with error ($?)"

log "Dar has completed with status $?"
log "Removing working dir $WORKING_DIR"

rm -rf "$WORKING_DIR" 2>&1 | logstdin

log "Uploading log file to s3://$TARGET_BUCKET/$LOGFILE"
aws s3 cp $LOGFILE s3://$TARGET_BUCKET/$LOGFILE

case $ON_COMPLETION in
	TERMINATE)
		aws sns publish --topic-arn $STATUS_UPDATE_ARN --message "($ARCHIVE_BASENAME) Backup has completed, terminating"
		aws ec2 terminate-instances  --instance-ids $EC2_INSTANCE_ID
	;;
	STOP)
		aws sns publish --topic-arn $STATUS_UPDATE_ARN --message "($ARCHIVE_BASENAME) Backup has completed, stopping"
		aws ec2 stop-instances --instance-ids $EC2_INSTANCE_ID
	;;
	*)
		aws sns publish --topic-arn $STATUS_UPDATE_ARN --message "($ARCHIVE_BASENAME)  Backup has completed, instance running"
	;;
esac
