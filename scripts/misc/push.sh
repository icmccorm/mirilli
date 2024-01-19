#!/bin/bash
INDEX=1
while IFS=, read address _ <&3; do 
  echo "Starting job $INDEX on EC2 instance $address"
  ssh -o "StrictHostKeyChecking=no" -i ~/.ssh/ffickle.pem ec2-user@$address "screen -d -m ./stage3.sh ./patch.csv"
  INDEX=$((INDEX+1))
done 3<$1