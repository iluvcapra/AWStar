#!/usr/bin/env bash

echo $0 ====================

name=`expr $TAR_ARCHIVE : '\(.*\)\.[0-9]*.tar'`

echo "#" Preparing volume $TAR_VOLUME of $name.

#if [ `expr $TAR_VOLUME % 5` == "0" ]; then
#		aws sns publish --topic-arn $STATUS_UPDATE_ARN --message "Preparing volume $TAR_VOLUME of $name"
#fi


case $TAR_SUBCOMMAND in
-c)     
	awstar_write_volume.sh $TAR_ARCHIVE $ARCHIVE_BASE_PREFIX_S3URL 
        NEXT_NAME=`printf "$name.%03i.tar" "$TAR_VOLUME"`
	echo $NEXT_NAME >&$TAR_FD
;;

esac
