#!/bin/bash
INDEX=1
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
    echo "$address,$STATUS,$EXIT_CODE" >> ./pulled/status.csv
    (ssh -i ~/.ssh/ffickle.pem -o "StrictHostKeyChecking=no" "ec2-user@$address" "./extract.sh results_$INDEX.zip")
    (scp -i ~/.ssh/ffickle.pem -o "StrictHostKeyChecking=no" "ec2-user@$address":~/results_$INDEX.zip ./pulled/)
    INDEX=$((INDEX+1))
done 3<$1