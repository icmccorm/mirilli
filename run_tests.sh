#!/bin/bash
export PATH="$HOME/.cargo/bin:$PATH"
rm -rf ./data/results/execution
rm -rf ./extracted
mkdir -p ./data/results/execution
mkdir -p ./data/results/execution/crates
touch ./data/results/execution/failed_download.csv
touch ./data/results/execution/failed_rustc_compilation.csv
touch ./data/results/execution/failed_miri_compilation.csv
touch ./data/results/execution/visited.csv
touch ./data/results/execution/status.csv
CURRENT_CRATE=""
while IFS=, read -r test_name crate_name version <&3; 
do
    # if the current crate is not an empty string,
    # and crate_name is not the same as the current crate
    SUCCEEDED_DOWNLOADING=0
    if [ "$CURRENT_CRATE" != "" ] && [ "$crate_name" != "$CURRENT_CRATE" ]; then
        rm -rf ./extracted
        TRIES_REMAINING=3
        while [ "$TRIES_REMAINING" -gt "0" ]; do
            echo "Downloading $crate_name@$version..."
            cargo-download -x "$crate_name==$version" --output ./extracted
            EXITCODE=$?
            TRIES_REMAINING=$(( TRIES_REMAINING - 1 ))
            if [ "$EXITCODE" -eq "0" ]; then
                echo "$crate_name,$version" >> ./data/results/tests/visited.csv
                echo "Precompiling miri"
                timeout 10m cargo miri test -q -- --list > /dev/null
                MIRI_FAILED=$?
                if [ "$MIRI_FAILED" -ne 0 ]; then
                    echo "Failed to precompile tests for miri"
                    echo "$crate_name,$version,$RUSTC_FAILED" >> "../data/results/tests/failed_miri_compilation.csv"
                else
                    SUCCEEDED_DOWNLOADING=1
                fi
            else
                echo "FAILED (exit $EXITCODE)"
                if [ "$TRIES_REMAINING" -eq "0" ]; then
                    echo "$crate_name,$version,$EXITCODE" >> "./data/results/tests/failed_download.csv"
                else
                    echo "PAUSE..."
                    sleep 10
                    echo "RETRY..."
                fi
            fi
        done
    else
        SUCCEEDED_DOWNLOADING=1
    fi
    TRIES_REMAINING=3
    CURRENT_CRATE="$crate_name"
    if [ "$SUCCEEDED_DOWNLOADING" -eq "1" ]; then
        echo "Running NORMAL test, $test_name..."
        EXITCODE=0
        OUTPUT=$(MIRIFLAGS=-Zmiri-disable-isolation timeout 60s cargo miri test -q "$test_name" -- --exact 2> err)
        EXITCODE=$?
        echo "$EXITCODE,$crate_name,\"$test_name\"" >> ./data/results/execution/status.csv
        if [ "$EXITCODE" -ne 0 ]; then
            if [ "$EXITCODE" -ne 124 ]; then
                mkdir -p "./data/results/execution/crates/$crate_name"
                cp err "./data/results/execution/crates/$crate_name/$test_name.log"
            fi
        fi
    fi
done 3< "$1"
printf 'FINISHED!\n'