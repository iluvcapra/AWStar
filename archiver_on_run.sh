#!/bin/bash
RUNDATE=`date "+%Y%m%d_%H%M"`
LOGFILE="${RUNDATE}_archivist.log.txt"
STATUS_UPDATE_ARN="arn:aws:sns:us-east-1:826181281546:jamiehardt_internal_notifications"
SHARED_FOLDER_DIR="/media/egnyte/Shared"

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
 		aws sns publish --topic-arn $STATUS_UPDATE_ARN \
		--message "FATAL: Error ($status) $*"
 	fi
 	exit $status
}

EC2_INSTANCE_ID=`ec2metadata --instance-id`

test -n "$EC2_INSTANCE_ID" || die -1 'cannot obtain instance-id'

EC2_AVAIL_ZONE=`ec2metadata --availability-zone`
test -n "$EC2_AVAIL_ZONE" || die -1 'cannot obtain availability-zone'

EC2_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed -e 's:\([0-9][0-9]*\)[a-z]*\$:\\1:'`"
EC2_USER_DATA=$(ec2metadata --user-data)

mount https://jamiehardt.egnyte.com/webdav 2>&1 >> $LOGFILE 

if [ $? != 0 ]; then
	die $? "Failed to mount egnyte webdav server"
fi

BUCKET_LIST=$(aws s3api list-buckets | awk '{if ($1 == "BUCKETS"){print $3}}')

indent() {
	awk '{print "    ", substr($0,0,75)}'
}

cat > "$LOGFILE" <<REP
===================== ARCHIVE SYSTEM RUN ======================
Starting report $(date)

Instance metadata:
$(ec2metadata | indent)

Notification ARN: $STATUS_UPDATE_ARN

Visible Shared Folders:
$(ls -1 $SHARED_FOLDER_DIR | indent )
Count: $(ls -1 $SHARED_FOLDER_DIR | wc -l) 

Visible buckets:
$(echo "$BUCKET_LIST" | indent )

REP

echo "" >> $LOGFILE

IS_WORKER="false"
case $EC2_USER_DATA in
	"WORKER")
	echo "WORKER MODE detected. Instance will terminate on script completion." >> $LOGFILE
	IS_WORKER="true"
	;;
	*)
	echo "WORKER MODE not detected.  Instance will continue to run on script completion." >> $LOGFILE
	;;
esac


## do work here

if [ $IS_WORKER = "true" ]; then
	NEXT_RUN_IDIOMATIC='11:00 next Sunday'
	NEXT_RUN_DATE_AZ=$(date --date="$NEXT_RUN_IDIOMATIC" '+%Y-%m-%dT%R:%SZ')
	NEXT_RUN_DATE=$(date --date="$NEXT_RUN_IDIOMATIC")	
	echo "Next instance will be scheduled for run at: $NEXT_RUN_DATE" >> $LOGFILE
	
	#schedule next run here
fi

echo "Closing report at $(date)" >> $LOGFILE
cp $LOGFILE /media/egnyte/Private/archivist/$LOGFILE || die $? 'failed to copy logfile'

umount /media/egnyte || die $? 'failed to unmount jamiehardt.egnyte.com'

if [ $IS_WORKER = "true" ]; then
	aws ec2 terminate-instances --instance-ids $EC2_INSTANCE_ID || \
	die $? 'failed to terminate instance' 
fi

