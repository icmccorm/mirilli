#!/bin/bash
INDEX=1
while IFS=, read address _ <&3; do 
  echo "Starting job $INDEX on EC2 instance $address"
  ssh -o "StrictHostKeyChecking=no" -i ~/.ssh/ffickle.pem ec2-user@$address "screen -d -m ./run_exec.sh ./data/partitions/tests/$INDEX.csv"
  INDEX=$((INDEX+1))
done 3<$1