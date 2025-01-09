#!/bin/bash

HELPTEXT="
Usage: ./run.sh <DIR> <stage2.csv>

The purpose of this step is to execute each of the tests found in 
Stage 1 find tests that call foreign functions.

Results are stored in <DIR>/stage2. Existing results will be overwritten.
The input to this step is the file stage2.csv, which is produced by 
compiling the results for Stage 1. 

Additional details are documented in DATASET.md
"
if [ "$#" -ne 2 ]; then
    echo "$HELPTEXT"
    exit 1
fi
if [ ! -f $2 ]; then
    echo "Unable to locate list of candidate crates."
    exit 1
fi

export DEFAULT_FLAGS="-g -O0 --save-temps=obj"
export CC="clang-16 $DEFAULT_FLAGS"
export CXX="clang++-16 $DEFAULT_FLAGS"
export PATH="$HOME/.cargo/bin:$PATH"

DIR="$1/stage2"
rm -rf $DIR
rm -rf ./extracted
STATUS_RUSTC_CSV="$DIR/status_rustc_comp.csv"
STATUS_MIRI_CSV="$DIR/status_miri_comp.csv"
FAILED_DOWNLOAD_CSV="$DIR/status_download.csv"
VISITED_CSV="$DIR/visited.csv"
TESTS_CSV="$DIR/tests.csv"

mkdir -p $DIR
mkdir -p $DIR/info/
mkdir -p $DIR/logs/
touch $FAILED_DOWNLOAD_CSV
touch $STATUS_MIRI_CSV
touch $STATUS_RUSTC_CSV
touch $VISITED_CSV
touch $TESTS_CSV

CRATE_COLNAMES="crate_name,version"
STATUS_COLNAMES="$CRATE_COLNAMES,exit_code"
echo "$CRATE_COLNAMES" > $VISITED_CSV
echo "$STATUS_COLNAMES" > $STATUS_MIRI_CSV
echo "$STATUS_COLNAMES" > $STATUS_RUSTC_CSV
echo "$STATUS_COLNAMES" > $FAILED_DOWNLOAD_CSV
echo "exit_code,had_ffi,test_name,crate_name" > $TESTS_CSV

TIMEOUT=10m
TIMEOUT_MIRI=5m
rustup override set nightly-2023-09-25
while IFS=, read -r crate_name version <&3; 
do
    unset -v IFS
    TRIES_REMAINING=3
    while [ "$TRIES_REMAINING" -gt "0" ]; do
        echo "Downloading $crate_name@$version..."
        (cargo-download "$crate_name==$version" -x -o extracted)
        EXITCODE=$?
        TRIES_REMAINING=$(( TRIES_REMAINING - 1 ))
        if [ "$EXITCODE" -eq "0" ]; then 
            echo "Download successful"
            TRIES_REMAINING=0
            RUSTC_FAILED=0
            cd extracted || return
            echo "Getting test list from rustc"
            RUSTC_TEST_OUTPUT=$(timeout $TIMEOUT cargo test --tests -- --list 2> err)
            RUSTC_EXIT_CODE=$?
            echo "$RUSTC_TEST_OUTPUT" | sed 's/: test$//' | sed 's/^\(.*\) -.*(line \([0-9]*\))/\1 \2/' > rustc_list.txt
            echo "$crate_name,$version,$RUSTC_EXIT_CODE" >> "../$DIR/status_rustc_comp.csv"
            if [ "$RUSTC_EXIT_CODE" -eq "0" ] && [ "$(wc -l < ./rustc_list.txt)" -ne 0 ]; then
		        echo "Precompiling miri"
                (timeout $TIMEOUT cargo miri test --tests -q -- --list > /dev/null)
                MIRI_EXIT_CODE=$?
                echo "$crate_name,$version,$RUSTC_FAILED" >> "../$DIR/status_miri_comp.csv"
                if [ "$MIRI_EXIT_CODE" -eq "0" ]; then
                    OUTPUT_DIR="../$DIR/logs/$crate_name/"
                    mkdir -p "$OUTPUT_DIR"
                    cp ./rustc_list.txt "$OUTPUT_DIR/population.csv"
                    while read -r test_name <&4;
                    do
                        if [ -z "$test_name" ]; then
                            continue
                        fi
                        rm -f err
                        touch err
                        EXITCODE=1
                        HAD_FFI=0
                        OUTPUT=""
                        if [[ $test_name =~ ^[0-9]*\ test[s]*,\ [0-9]*\ benchmark[s]*$ ]]; then
                            echo "Skipping benchmarks test, $test_name..."
                            continue
                        fi
                        if [[ $test_name =~ ^.*\ [0-9]*$ ]]; then
                            echo "Skipping DOC test, $test_name..."
                            continue
                        else
                            echo "Running NORMAL test, $test_name..."
			                OUTPUT=$(MIRIFLAGS="-Zmiri-disable-isolation" timeout $TIMEOUT_MIRI cargo miri test --tests -q "$test_name" -- --exact 2> err)
                            EXITCODE=$?
                        fi
                        echo "$OUTPUT" > "$OUTPUT_DIR/$test_name.out.log"
                        cp ./err "$OUTPUT_DIR/$test_name.err.log"
                        if [ "$EXITCODE" -ne 0 ]; then
                            echo "Exit code is $EXITCODE"
                            grep -q "error: unsupported operation: can't call foreign function" ./err
                            HAD_FFI=$?
                            if [ "$HAD_FFI" -eq "0" ]; then
                                echo "Miri found FFI call for $test_name"
                            else
                                echo "Miri failed for $test_name."
                            fi
                        else
                            HAD_FFI="-1"
                            if echo "$OUTPUT" | grep -q "1 passed"; then
                                echo "Miri passed for $test_name"
                            else
                                echo "Miri disabled for $test_name"
                                EXITCODE="-1"
                            fi
                        fi
                        echo "$EXITCODE,$HAD_FFI,\"$test_name\",$crate_name" >> "../$TESTS_CSV"
                        rm -f err 
                    done 4< ./rustc_list.txt
                fi
            fi
            cd ..
        else
            echo "FAILED (exit $EXITCODE)"
            if [ "$TRIES_REMAINING" -eq "0" ]; then
                echo "$crate_name,$version,$EXITCODE" >> "./$DIR/status_download.csv"
            else
                echo "PAUSE..."
                sleep 10
                echo "RETRY..."
            fi
        fi
    done
    rm -rf ./extracted
    TRIES_REMAINING=3
    IFS=,
    echo "$crate_name,$version" >> $VISITED_CSV
done 3< "$2"
printf 'FINISHED!\n'