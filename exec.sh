#!/bin/bash
export PATH="$HOME/.cargo/bin:$PATH"
make clean && make all
rm -rf ./data/results
mkdir -p ./data/results
mkdir -p ./data/results/early
mkdir -p ./data/results/late
TRIES_REMAINING=3
while IFS=, read -r name version; 
do
    while [ "$TRIES_REMAINING" -gt "0" ]; do
        cargo-download -x "$name==$version" --output ./test
        EXITCODE=$?
        TRIES_REMAINING=$(( TRIES_REMAINING - 1 ))
        if [ "$EXITCODE" -eq "0" ]; then 
            echo "SUCCESS"
            TRIES_REMAINING=0
            if ! (cd test && (timeout 5m cargo dylint --all 1> /dev/null)); then
                COMP_EXIT_CODE=$?
                echo "Writing failure to data/results/failed_compilation.csv"
                echo "$name,$version,$COMP_EXIT_CODE" >> "data/results/failed_compilation.csv"
            fi
            echo "Writing visit to data/results/visited.csv"
            echo "$name,$version" >> "data/results/visited.csv"
            echo "Copying analysis output to data/results/early/$name.json"
            [ ! -f ./test/ffickle_early.json ] || mv ./test/ffickle_early.json "data/results/early/$name.json"
            echo "Copying analysis output to data/results/late/$name.json"
            [ ! -f ./test/ffickle_late.json ] || mv ./test/ffickle_late.json "data/results/late/$name.json"
        else
            echo "FAILED (exit $EXITCODE)"
            if [ "$TRIES_REMAINING" -eq "0" ]; then
                echo "$name,$version,$EXITCODE" >> "data/results/failed_download.csv"
            else
                echo "PAUSE..."
                sleep 10
                echo "RETRY..."
            fi
        fi
        rm -rf ./test
    done
    TRIES_REMAINING=3
done <<< "$(tail -n +2 "$1")"
printf 'FINISHED! %s\n' "$name"
