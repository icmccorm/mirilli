#!/bin/bash
export PATH="$HOME/.cargo/bin:$PATH"
rm -rf ./data/results/tests
rm -rf ./extracted
mkdir -p ./data/results/tests
mkdir -p ./data/results/tests/info
touch ./data/results/tests/failed_download.csv
touch ./data/results/tests/failed_rustc_compilation.csv
touch ./data/results/tests/failed_miri_compilation.csv
touch ./data/results/tests/visited.csv
while IFS=, read -r crate_name version; 
do
    unset -v IFS
    TRIES_REMAINING=3
    while [ "$TRIES_REMAINING" -gt "0" ]; do
        echo "Downloading $crate_name@$version..."
        cargo-download -x "$crate_name==$version" --output ./extracted
        EXITCODE=$?
        TRIES_REMAINING=$(( TRIES_REMAINING - 1 ))
        if [ "$EXITCODE" -eq "0" ]; then 
            echo "Download successful"
            TRIES_REMAINING=0
            RUSTC_FAILED=0
            cd extracted || return
            echo "Getting test list from rustc"
            timeout 5m cargo test -q -- --list | sed 's/: test$//' | sed 's/^\(.*\) -.*(line \([0-9]*\))/\1 \2/' > rustc_list.txt
            RUSTC_FAILED=${PIPESTATUS[0]}
            if [ "$RUSTC_FAILED" -ne 0 ]; then
                echo "Failed to get test list from rustc"
                echo "$crate_name,$version,$RUSTC_FAILED" >> "../data/results/tests/failed_rustc_compilation.csv"
            fi
            # if miri and rustc succeeded
            if [ "$RUSTC_FAILED" -eq "0" ] && [ "$(wc -l < ./rustc_list.txt)" -ne 0 ]; then
                OUTPUT_FILE="../data/results/tests/info/$crate_name-$version.csv"
                echo "Logging tests to $OUTPUT_FILE"
                while read -r test_name; 
                do
                    touch err
                    if [[ $test_name =~ ^[0-9]*\ test[s]*,\ [0-9]*\ benchmark[s]*$ ]]; then
                        continue
                    fi
                    # if $test_name is of the form "filename line_number"
                    if [[ $test_name =~ ^.*\ [0-9]*$ ]]; then
                        echo "Running DOC test, $test_name..."
                        OUTPUT=$(MIRIFLAGS=-Zmiri-disable-isolation timeout 30s cargo miri test -q -- --doc "$test_name" 2> err)
                    else
                        echo "Running NORMAL test, $test_name..."
                        OUTPUT=$(MIRIFLAGS=-Zmiri-disable-isolation timeout 30s cargo miri test -q "$test_name" -- --exact 2> err)
                    fi
                    EXITCODE=$?
                    if [ "$EXITCODE" -ne 0 ]; then
                        grep -q "error: unsupported operation: can't call foreign function" ./err
                        HAD_FFI=$?
                        if [ "$HAD_FFI" -eq "0" ]; then
                            echo "Miri found FFI call for $test_name"
                        else
                            echo "Miri failed for $test_name."
                        fi
                    else
                        HAD_FFI=0
                        if echo $OUTPUT | grep -q "1 passed"; then
                            echo "Miri passed for $test_name"
                        else
                            echo "Miri disabled for $test_name"
                            EXITCODE="-1"
                        fi
                    fi
                    echo "$EXITCODE,$HAD_FFI,\"$test_name\"" >> "$OUTPUT_FILE"
                    rm -f err 
                done < ./rustc_list.txt
            fi
            cd ..
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
    rm -rf ./extracted
    TRIES_REMAINING=3
    IFS=,
    echo "$crate_name,$version" >> ./data/results/tests/visited.csv
done < $1
printf 'FINISHED! %s\n' "$crate_name"