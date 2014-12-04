#!/usr/bin/env bash

#awstar_init.sh

AWSTAR_INIT_PATH=~/.awstar

if [ -e $AWSTAR_INIT_PATH ]; then
	echo "Loading confing from $AWSTAR_INIT_PATH"
else
	cat > $AWSTAR_INIT_PATH <<-initdata
## AWSTAR Configuration
#
# 

# An ARN for an SNS URI that will receive notifications about archive progress
AWSTAR_UPDATE_ARN="arn:aws:sns:your-update-arn"

# A prefix for the S3 buckets that will save your archives. These must be globally
# unique and will be followed by something like "-arch-2014"
AWSTAR_S3_BUCKET_PREFIX="globally-unique-prefix"
initdata
	vim $AWSTAR_INIT_PATH
fi

source $AWSTAR_INIT_PATH

export AWSTAR_UPDATE_ARN
export AWSTAR_S3_BUCKET_PREIX
