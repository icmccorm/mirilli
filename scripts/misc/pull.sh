#!/bin/bash
INDEX=2
rm -rf ./pulled
mkdir ./pulled
touch ./pulled/status.csv
echo "address,status,exit_code" >> ./pulled/status.csv
while IFS=, read address _ <&3; do 
    echo $address
    (ssh -i ~/.ssh/ffickle.pem -o "StrictHostKeyChecking=no" "ec2-user@$address" "docker container ls -la")
    OUTPUT=$(ssh -i ~/.ssh/ffickle.pem -o "StrictHostKeyChecking=no" "ec2-user@$address" "docker inspect ffickle --format={{.State.Status}}:{{.State.ExitCode}}")
    # split into status and exit code
    STATUS=$(echo $OUTPUT | cut -d ':' -f 1)
    EXIT_CODE=$(echo $OUTPUT | cut -d ':' -f 2)
    echo "$INDEX,$address,$STATUS,$EXIT_CODE" >> ./pulled/status.csv
    (ssh -i ~/.ssh/ffickle.pem -o "StrictHostKeyChecking=no" "ec2-user@$address" "./extract.sh")
    (scp -i ~/.ssh/ffickle.pem -o "StrictHostKeyChecking=no" "ec2-user@$address":~/results.zip ./pulled/results_$INDEX.zip)
    INDEX=$((INDEX+1))
done 3<$1