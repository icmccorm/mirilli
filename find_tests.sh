rm -rf ./data/results/tests
rm -rf ./extracted
mkdir -p ./data/results/tests
mkdir -p ./data/results/tests/lists
mkdir -p ./data/results/tests/status
touch ./data/results/tests/failed_download.csv
touch ./data/results/tests/failed_rustc_compilation.csv
touch ./data/results/tests/failed_miri_compilation.csv
touch ./data/results/tests/miri_timeout.csv
while IFS=, read -r name version; 
do
    TRIES_REMAINING=3
    while [ "$TRIES_REMAINING" -gt "0" ]; do
        cargo-download -x "$name==$version" --output ./extracted
        EXITCODE=$?
        TRIES_REMAINING=$(( TRIES_REMAINING - 1 ))
        if [ "$EXITCODE" -eq "0" ]; then 
            echo "SUCCESS"
            TRIES_REMAINING=0
            MIRI_FAILED=0
            RUSTC_FAILED=0
            cd extracted
            if ! (timeout 5m cargo test -q -- --list > rustc_list.txt); then
                RUSTC_FAILED=1
                COMP_EXIT_CODE=$?
                echo "Writing failure to data/results/failed_rustc_compilation.csv"
                echo "$name,$version,$COMP_EXIT_CODE" >> "data/results/failed_rustc_compilation.csv"
            fi
            if ! (timeout 5m cargo miri test -q -- --list > miri_list.txt); then
                MIRI_FAILED=1
                COMP_EXIT_CODE=$?
                echo "Writing failure to data/results/failed_rustc_compilation.csv"
                echo "$name,$version,$COMP_EXIT_CODE" >> "data/results/failed_miri_compilation.csv"
            fi
            # if miri and rustc succeeded
            if [ "$MIRI_FAILED" -eq "0" ] && [ "$RUSTC_FAILED" -eq "0" ]; then
                cat -n ./miri_list.txt ./rustc_list.txt | sort -uk2 | sort -nk1 | cut -f2- | sed 's/: test$//' | sed 's/^\(.*\) -.*(line \([0-9]*\))/\1 \2/' > miri_list_final.txt
                touch ./failed_ffi.txt
                while IFS=" " read -r name line; 
                do
                    touch err
                    if [ -z "$line" ]; then  
                        echo "Running $name..."
                        timeout 1m cargo miri test -q "$name" -- --exact 2> err
                    else 
                        echo "Running $name $line..."
                        timeout 1m cargo miri test -q -- --doc "$name $line" 2> err
                    fi
                    FAILED_FROM_FFI=$(grep -q "error: unsupported operation: can't call foreign function" ./err)
                    # check if FAILED_FROM_FFI had a match
                    if [[ "$FAILED_FROM_FFI" -eq "0" ]]; then
                        echo "$name $line" >> ./failed_ffi.txt
                    fi
                    rm -f err
                done < ./miri_list_final.txt
                cp ./miri_list_final.txt "../data/results/tests/lists/$name_$version.txt"
                cp ./failed_ffi.txt "../data/results/tests/status/$name_$version.txt"
                rm ./failed_ffi.txt
                rm ./miri_list_final.txt
            fi
            cd ..
        else
            echo "FAILED (exit $EXITCODE)"
            if [ "$TRIES_REMAINING" -eq "0" ]; then
                echo "$name,$version,$EXITCODE" >> "data/results/tests/failed_download.csv"
            else
                echo "PAUSE..."
                sleep 10
                echo "RETRY..."
            fi
        fi
        rm -rf ./extracted
    done
    TRIES_REMAINING=3
done <<< "$(tail -n +2 "$1")"
printf 'FINISHED! %s\n' "$name"