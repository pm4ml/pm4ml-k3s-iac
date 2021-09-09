#!/bin/sh

set -e
aws --region $3 dynamodb delete-item --table-name $1 --key '{"LockID": {"S": '\"$2'/terraform.tfstate-md5"}}' --return-values ALL_OLD