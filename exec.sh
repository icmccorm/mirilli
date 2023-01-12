#!/bin/bash
source "$HOME/.cargo/env"
RED='\e[1;31m'
GREEN='\e[1;32m'
NC='\e[1;0m'
make clean && make all
rm -rf ./data/results
mkdir -p ./data/results
mkdir -p ./data/results/early
mkdir -p ./data/results/late
TO_VISIT=$(cat $1)
while IFS=, read name version; 
do
    if (cargo-download -x "$name==$version" --output ./test 1> /dev/null); then 
	if ! (cd test && (timeout 5m cargo dylint --all 1> /dev/null)); then
            echo "Writing failure to data/results/failed_compilation.csv"
            echo "$name,$version,$?" >> "data/results/failed_compilation.csv"
        fi
        echo "Writing visit to data/results/visited.csv"
        echo "$name,$version" >> "data/results/visited.csv"
        echo "Copying analysis output to data/results/early/$name-$version.json"
        [ ! -f ./test/ffickle_early.json ] || mv ./test/ffickle_early.json "data/results/early/$name-$version.json"
        echo "Copying analysis output to data/results/late/$name-$version.json"
        [ ! -f ./test/ffickle_late.json ] || mv ./test/ffickle_late.json "data/results/late/$name-$version.json"
    else
        echo "${RED}DOWNLOAD FAILED${NC} $name $version\n"
        echo "$name,$version,$?" >> "data/results/failed_download.csv"
    fi
    rm -rf ./test
done <<< "$TO_VISIT"
echo "${GREEN} FINISHED! ${NC} $name\n"
