#!/bin/bash

HELPTEXT="
Usage: ./run.sh <DIR>

The purpose of this step is to determine which crates contain unit
tests and produce LLVM bitcode during compilation. We also analyze the
source code of each crate to find foreign function bindings.

The directory <DIR> must contain the file "population.csv". This file
must contain two labelled columns "crate_name" and "version" in that order.

Results are stored in <DIR>/stage1. Existing results will be overwritten.

Additional details are documented in DATASET.md
"
if [ "$#" -ne 1 ]; then
    echo "$HELPTEXT"
    exit 1
fi
if [ ! -f $1/population.csv ]; then
    echo "Unable to locate $1/population.csv!"
fi

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

DIR=$1/stage1
rm -rf "$DIR"
mkdir -p "$DIR"
mkdir -p "$DIR/early"
mkdir -p "$DIR/late"
mkdir -p "$DIR/tests"
mkdir -p "$DIR/bytecode"
touch "$DIR/status_comp.csv"
touch "$DIR/status_lint.csv"
touch "$DIR/status_download.csv"
touch "$DIR/has_bytecode.csv"
rustup override set "$NIGHTLY"

CRATE_COLNAMES="crate_name,version"
STATUS_COLNAMES="$CRATE_COLNAMES,exit_code"
echo "$CRATE_COLNAMES" > "$DIR/visited.csv"
echo "$CRATE_COLNAMES" > "$DIR/has_bytecode.csv"
echo "$STATUS_COLNAMES" > "$DIR/status_comp.csv"
echo "$STATUS_COLNAMES" > "$DIR/status_lint.csv"
echo "$STATUS_COLNAMES" > "$DIR/status_download.csv"
TRIES_REMAINING=3
while IFS=, read -r name version; 
do
    while [ "$TRIES_REMAINING" -gt "0" ]; do

        echo $name $version
        EXITCODE=1
        (cargo-download "$name==$version" -x -o extracted)
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
            echo "$name,$version,$COMP_EXIT_CODE" >> $DIR/status_comp.csv
            if [ -n "$OUTPUT" ]; then
                echo "$OUTPUT" > $DIR/tests/"$name".txt
            fi
            OUTPUT=""
            OUTPUT=$(find ./extracted -type f -name '*.bc' -print -quit)
            if [ -n "$OUTPUT" ]; then
                echo "Writing visit to $DIR/has_bytecode.csv"
                echo "$name,$version" >> $DIR/has_bytecode.csv
                echo "$OUTPUT" > $DIR/bytecode/"$name".csv
            fi
            COMP_EXIT_CODE=1
            cd extracted || exit
            (timeout $TIMEOUT cargo dylint --all 1> /dev/null)
            COMP_EXIT_CODE=$?
            cd ..
            echo "$name,$version,$COMP_EXIT_CODE" >> "$DIR/status_lint.csv"

            echo "Writing visit to $DIR/visited.csv"
            echo "$name,$version" >> "$DIR/visited.csv"
            echo "Copying analysis output to $DIR/early/$name.json"
            [ ! -f ./extracted/ffickle_early.json ] || mv ./extracted/ffickle_early.json "$DIR/early/$name.json"
            echo "Copying analysis output to $DIR/late/$name.json"
            [ ! -f ./extracted/ffickle_late.json ] || mv ./extracted/ffickle_late.json "$DIR/late/$name.json"
        else
            echo "FAILED (exit $EXITCODE)"
            if [ "$TRIES_REMAINING" -eq "0" ]; then
                echo "$name,$version,$EXITCODE" >> "$DIR/status_download.csv"
            else
                echo "PAUSE..."
                sleep 10
                echo "RETRY..."
            fi
        fi
        rm -rf ./extracted
    done
    TRIES_REMAINING=3
done <<< "$(tail -n +2 "$1/population.csv")"

printf 'FINISHED!\n'