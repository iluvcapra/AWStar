#!/bin/bash

aws ec2 stop-instances --instance-ids=`ec2metadata --instance-id`

