#!/bin/bash
rm -rf ./data/results/tests
rm -rf ./extracted
mkdir -p ./data/results/tests
mkdir -p ./data/results/tests/info
touch ./data/results/tests/failed_download.csv
touch ./data/results/tests/failed_rustc_compilation.csv
echo "crate_name,version,exit_code" >> ./data/results/tests/failed_rustc_compilation.csv
touch ./data/results/tests/failed_miri_compilation.csv
echo "crate_name,version,exit_code" >> ./data/results/tests/failed_miri_compilation.csv
while IFS=, read -r crate_name version; 
do
    TRIES_REMAINING=3
    while [ "$TRIES_REMAINING" -gt "0" ]; do
        cargo-download -x "$crate_name==$version" --output ./extracted
        EXITCODE=$?
        TRIES_REMAINING=$(( TRIES_REMAINING - 1 ))
        if [ "$EXITCODE" -eq "0" ]; then 
            echo "SUCCESS"
            TRIES_REMAINING=0
            MIRI_FAILED=0
            RUSTC_FAILED=0
            cd extracted
            timeout 5m cargo test -q -- --list | sed 's/: test$//' | sed 's/^\(.*\) -.*(line \([0-9]*\))/\1 \2/' > rustc_list.txt
            RUSTC_FAILED=$PIPESTATUS
            if [ $RUSTC_FAILED -ne 0 ]; then
                echo "$crate_name,$version,$RUSTC_FAILED" >> "../data/results/tests/failed_rustc_compilation.csv"
            fi
            if [ $RUSTC_FAILED -eq 0 ]; then
                timeout 5m cargo miri test -q -- --list | sed 's/: test$//' | sed 's/^\(.*\) -.*(line \([0-9]*\))/\1 \2/' > miri_list.txt
                MIRI_FAILED=$PIPESTATUS
                if [ $MIRI_FAILED -ne 0 ]; then
                    echo "$crate_name,$version,$MIRI_FAILED" >> "../data/results/tests/failed_miri_compilation.csv"
                fi            
            fi
            # if miri and rustc succeeded
            if [ "$MIRI_FAILED" -eq "0" ] && [ "$RUSTC_FAILED" -eq "0" ] && [ $(cat ./rustc_list.txt | wc -l) -ne 0 ]; then
                OUTPUT_FILE="../data/results/tests/info/$crate_name-$version.csv"
                echo "exit_code,failed_from_ffi,test_name" > $OUTPUT_FILE
                comm -13 ./miri_list.txt ./rustc_list.txt | sed 's/^/-1,-1,/' >> $OUTPUT_FILE
                while IFS=" " read -r test_name line; 
                do
                    touch err
                    if [ -z "$line" ]; then  
                        echo "Running $test_name..."
                        MIRIFLAGS=-Zmiri-disable-isolation timeout 1m cargo miri test -q "$test_name" -- --exact 2> err
                    else 
                        echo "Running $test_name $line..."
                        MIRIFLAGS=-Zmiri-disable-isolation timeout 1m cargo miri test -q -- --doc "$test_name $line" 2> err
                    fi
                    EXITCODE=$?
                    grep -q "error: unsupported operation: can't call foreign function" ./err
                    echo "$EXITCODE,$?,$test_name $line" >> $OUTPUT_FILE
                    rm -f err
                done < ./miri_list.txt
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
    chown -R $USER ./extracted
    rm -rf ./extracted
    TRIES_REMAINING=3
done <<< "$(tail -n +2 "$1")"
printf 'FINISHED! %s\n' "$crate_name"