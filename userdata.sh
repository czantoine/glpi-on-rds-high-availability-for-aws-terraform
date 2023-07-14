#! /bin/bash
sudo apt-get update
sudo apt-get install awscli -y
aws s3 cp s3://<bucket-name>/script.sh ./script.sh
sudo bash script.sh
