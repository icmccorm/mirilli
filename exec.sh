#!/bin/bash
export PATH="$HOME/.cargo/bin:$PATH"
export DYLINT_LIBRARY_PATH="/usr/src/ffickle/src/early/target/debug/:/usr/src/ffickle/src/late/target/debug/"
rustup --version
rustc --version
cargo --version
make clean && make all
rm -rf ./data/results
mkdir -p ./data/results
#mkdir -p ./data/results/early
#mkdir -p ./data/results/late
echo crate_name,version,ffi_c_count,ffi_count,test_count,bench_count >> ./data/results/count.csv
TRIES_REMAINING=3
while IFS=, read -r name version; 
do
    while [ "$TRIES_REMAINING" -gt "0" ]; do
        cargo-download -x "$name==$version" --output ./extracted
        EXITCODE=$?
        TRIES_REMAINING=$(( TRIES_REMAINING - 1 ))
        if [ "$EXITCODE" -eq "0" ]; then 
            echo "SUCCESS"
            TRIES_REMAINING=0
            cd extracted
            NUM_TESTS_SRC=$(grep -r "#\[test\]" ./src | wc -l | xargs)
            NUM_TESTS_TESTS=$(grep -r "#\[test\]" ./tests | wc -l | xargs)
            NUM_TESTS_BENCHES=$(grep -r "#\[test\]" ./benches | wc -l | xargs)
            NUM_TESTS=$(($NUM_TESTS_SRC + $NUM_TESTS_TESTS + $NUM_TESTS_BENCHES))
            NUM_BENCHES_SRC=$(grep -r "#\[bench\]" ./src | wc -l | xargs)
            NUM_BENCHES_TESTS=$(grep -r "#\[bench\]" ./tests | wc -l | xargs)
            NUM_BENCHES_BENCHES=$(grep -r "#\[bench\]" ./benches | wc -l | xargs)
            NUM_BENCHES=$(($NUM_BENCHES_SRC + $NUM_BENCHES_TESTS + $NUM_BENCHES_BENCHES))
            NUM_FFI_C=$(grep -r 'extern\s*\(\"\(C\)\(-unwind\)\?\"\)\?\s*\(fn\|{\)' --include '*.rs' | wc -l | xargs)
            NUM_FFI=$(grep -r 'extern\s*\(\"\(C\|cdecl\|stdcall\|fastcall\|vectorcall\|thiscall\|aapcs\|win64\|sysv64\|ptx-kernel\|msp430-interrupt\|x86-interrupt\|amdgpu-kernel\|efiapi\|avr-interrupt\|avr-non-blocking-interrupt\|C-cmse-nonsecure-call\|wasm\|system\|platform-intrinsic\|unadjusted\)\(-unwind\)\?\"\)\?\s*\(fn\|{\)' --include '*.rs' | wc -l | xargs)
            cd ..
            echo "$name,$version,$NUM_FFI_C,$NUM_FFI,$NUM_TESTS,$NUM_BENCHES" >> ./data/results/count.csv

            #export DYLINT_LIBRARY_PATH="/usr/src/ffickle/src/early/target/debug/:/usr/src/ffickle/src/late/target/debug/"
            #if ! (cd extracted && (timeout 5m cargo dylint --all 1> /dev/null)); then
            #    COMP_EXIT_CODE=$?
            #    echo "Writing failure to data/results/failed_compilation.csv"
            #    echo "$name,$version,$COMP_EXIT_CODE" >> "data/results/failed_compilation.csv"
            #fi
            echo "Writing visit to data/results/visited.csv"
            echo "$name,$version" >> "data/results/visited.csv"
            #echo "Copying analysis output to data/results/early/$name.json"
            #[ ! -f ./extracted/ffickle_early.json ] || mv ./extracted/ffickle_early.json "data/results/early/$name.json"
            #echo "Copying analysis output to data/results/late/$name.json"
            #[ ! -f ./extracted/ffickle_late.json ] || mv ./extracted/ffickle_late.json "data/results/late/$name.json"
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
done <<< "$(tail -n +2 "$1")"
printf 'FINISHED! %s\n' "$name"
