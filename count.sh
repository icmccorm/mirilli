#!/bin/bash
export PATH="$HOME/.cargo/bin:$PATH"
rustup --version
rustc --version
cargo --version
rm -rf ./extracted
rm -rf ./data/results/count/
mkdir -p ./data/results
mkdir -p ./data/results/count
echo crate_name,version,ffi_c_count,ffi_count,test_count,bench_count >> ./data/results/testcount/count.csv
TRIES_REMAINING=3
while IFS=, read -r name version; 
do
    cargo-download -x "$name==$version" --output ./extracted
    EXITCODE=$?
    if [ "$EXITCODE" -eq "0" ]; then 
        echo "SUCCESS"
        cd extracted
        NUM_TESTS_SRC=$(grep -r "#\[test\]" ./src | wc -l | xargs)
        NUM_TESTS_TESTS=$(grep -r "#\[test\]" ./tests | wc -l | xargs)
        NUM_TESTS_BENCHES=$(grep -r "#\[test\]" ./benches | wc -l | xargs)
        NUM_TESTS=$(($NUM_TESTS_SRC + $NUM_TESTS_TESTS + $NUM_TESTS_BENCHES))

        NUM_BENCHES_SRC=$(grep -r "#\[bench\]" ./src | wc -l | xargs)
        NUM_BENCHES_TESTS=$(grep -r "#\[bench\]" ./tests | wc -l | xargs)
        NUM_BENCHES_BENCHES=$(grep -r "#\[bench\]" ./benches | wc -l | xargs)
        NUM_BENCHES=$(($NUM_BENCHES_SRC + $NUM_BENCHES_TESTS + $NUM_BENCHES_BENCHES))
        NUM_FFI_C=$(grep -r 'extern\s*\(\"\(C\)\(-unwind\)\?\"\)\?\s*\(fn\|{\)' *.rs | wc -l | xargs)
        NUM_FFI=$(grep -r 'extern\s*\(\"\(C\|cdecl\|stdcall\|fastcall\|vectorcall\|thiscall\|aapcs\|win64\|sysv64\|ptx-kernel\|msp430-interrupt\|x86-interrupt\|amdgpu-kernel\|efiapi\|avr-interrupt\|avr-non-blocking-interrupt\|C-cmse-nonsecure-call\|wasm\|system\|platform-intrinsic\|unadjusted\)\(-unwind\)\?\"\)\?\s*\(fn\|{\)' *.rs | wc -l | xargs)
        cd ..
        echo "$name,$version,$NUM_FFI_C,$NUM_FFI,$NUM_TESTS,$NUM_BENCHES" >> ./data/results/testcount/count.csv
    else
        echo "$name,$version,$EXITCODE" >> "./data/results/testcount/failed_download.csv"
    fi
    rm -rf ./extracted
done <<< "$(tail -n +2 "$1")"
printf 'FINISHED! %s\n' "$name"