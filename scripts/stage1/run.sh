#!/bin/bash
export PATH="$HOME/.cargo/bin:$PATH"
export DYLINT_LIBRARY_PATH="$PWD/src/early/target/debug/:$PWD/src/late/target/debug/"
export DEFAULT_FLAGS="-g -O0 --save-temps=obj"
export CC="clang-16 $DEFAULT_FLAGS"
export CXX="clang++-16 $DEFAULT_FLAGS"
export NIGHTLY="nightly-2023-09-25"
TIMEOUT=5m
rustup --version
rustc --version
cargo --version
make clean && make all
rm -rf ./data/results
mkdir -p ./data/results
mkdir -p ./dataset/early
mkdir -p ./dataset/late
mkdir -p ./dataset/tests
mkdir -p ./dataset/bytecode
touch ./dataset/status_comp.csv
touch ./dataset/status_lint.csv
touch ./dataset/failed_download.csv
touch ./dataset/has_bytecode.csv
rustup override set "$NIGHTLY"
TRIES_REMAINING=3
while IFS=, read -r name version; 
do
    while [ "$TRIES_REMAINING" -gt "0" ]; do
        EXITCODE=1
        (./scripts/misc/cargo-download.sh "$name" "$version")
        EXITCODE=$?
        TRIES_REMAINING=$(( TRIES_REMAINING - 1 ))
        if [ "$EXITCODE" -eq "0" ]; then 
            echo "SUCCESS"
            TRIES_REMAINING=0
            OUTPUT=""
            cd extracted || exit
            COMP_EXIT_CODE=1
            OUTPUT=$(timeout $TIMEOUT cargo test --tests -- --list)
            COMP_EXIT_CODE=$?
            cd ..
            echo "$name,$version,$COMP_EXIT_CODE" >> "data/results/status_comp.csv"
            if [ -n "$OUTPUT" ]; then
                echo "$OUTPUT" > data/results/tests/"$name".txt
            fi
            OUTPUT=""
            OUTPUT=$(find ./extracted -type f -name '*.bc' -print -quit)
            if [ -n "$OUTPUT" ]; then
                echo "Writing visit to data/results/has_bytecode.csv"
                echo "$name,$version" >> "data/results/has_bytecode.csv"
                echo "$OUTPUT" > data/results/bytecode/"$name".csv
            fi

            COMP_EXIT_CODE=1
            cd extracted || exit
            (timeout $TIMEOUT cargo dylint --all 1> /dev/null)
            COMP_EXIT_CODE=$?
            cd ..
            echo "$name,$version,$COMP_EXIT_CODE" >> "data/results/status_lint.csv"

            echo "Writing visit to data/results/visited.csv"
            echo "$name,$version" >> "data/results/visited.csv"
            echo "Copying analysis output to data/results/early/$name.json"
            [ ! -f ./extracted/ffickle_early.json ] || mv ./extracted/ffickle_early.json "data/results/early/$name.json"
            echo "Copying analysis output to data/results/late/$name.json"
            [ ! -f ./extracted/ffickle_late.json ] || mv ./extracted/ffickle_late.json "data/results/late/$name.json"
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
        rm -rf ./extracted
    done
    TRIES_REMAINING=3
done <<< "$(tail -n +0 "$1")"
printf 'FINISHED! %s\n' "$name"