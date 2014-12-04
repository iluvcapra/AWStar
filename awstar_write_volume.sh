#!/bin/bash

echo $0 ====================

echo "#" Creating volume $1 at S3 location $2

TAR_ARCHIVE=$1
S3URL_PREFIX=$2

FINAL_ARCH_NAME=$TAR_ARCHIVE.gpg

ENCRYPT_RECIPIENT=jamiehardt@aws.amazon.com

echo
echo "#" Compressing and encrypting volume with gpg...
gpg --encrypt -r "$ENCRYPT_RECIPIENT" < "$TAR_ARCHIVE" > $FINAL_ARCH_NAME

rm "$TAR_ARCHIVE"

echo
echo "#" Creating PAR2 redundancy data...
par2create -q $FINAL_ARCH_NAME

echo
echo "#" Uploading $FINAL_ARCH_NAME to S3...
aws s3 mv "$FINAL_ARCH_NAME" "$S3URL_PREFIX/$FINAL_ARCH_NAME"

echo
echo "#" Uploading PAR2 Segments...
aws s3 mv --recursive --exclude "*" --include "*.par2" "." "$S3URL_PREFIX/"

echo
echo "#" $1 Uploaded
echo --------------------------------------------------------------------------------
