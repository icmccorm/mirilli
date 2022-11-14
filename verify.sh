#!/bin/bash
RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m'
make clean && make all
mkdir -p "$2"
mkdir -p "$2/$1"
mkdir -p "$2/$1/early"
mkdir -p "$2/$1/late"
TO_VISIT=""
if test -f "$2/$1/visited.csv"; then
    cat "$2/$1/visited.csv" | sort > ./visited_sorted.csv;
    cat "./data/partitions/partition$1.csv" | sort > ./all_sorted.csv;
    TO_VISIT=$(comm -23 "./all_sorted.csv" "./visited_sorted.csv")
else
    TO_VISIT=$(cat ./data/partitions/partition$1.csv)
fi
while IFS=, read name version; 
do 
    if (cargo-download -x "$name==$version" --output ./test 1> /dev/null); then 
	    if ! (cd test && (timeout 5m cargo dylint --all 1> /dev/null)); then
            echo "Writing failure to $2/$1/failed.csv"
            echo "$name,$version,$?" >> "$2/$1/failed.csv"
        fi
        echo "Writing visit to $2/$1/visited.csv"
        echo "$name,$version" >> "$2/$1/visited.csv"
        echo "Copying analysis output to $2/$1/early/$name.json"
        [ ! -f ./test/ffickle_early.json ] || mv ./test/ffickle_early.json "$2/$1/early/$name.json"
        echo "Copying analysis output to $2/$1/late/$name.json"
        [ ! -f ./test/ffickle_late.json ] || mv ./test/ffickle_late.json "$2/$1/late/$name.json"
    else
        echo "${RED}DOWNLOAD FAILED${NC} $name\n"
    fi
    rm -rf ./test
done <<< "$TO_VISIT"
echo "${GREEN}FINISHED!${NC} $name\n"
