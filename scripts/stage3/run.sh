#!/bin/bash
export PATH="$HOME/.cargo/bin:$PATH"
export DEFAULT_FLAGS="-g -O0 --save-temps=obj"
export CC="clang-16 $DEFAULT_FLAGS"
export CXX="clang++-16 $DEFAULT_FLAGS"
rm -rf ./results/stage3
rm -rf ./extracted
mkdir -p ./results/stage3
mkdir -p ./results/stage3/crates
touch ./results/stage3/failed_download.csv
touch ./results/stage3/status_native_comp.csv
touch ./results/stage3/status_miri_comp.csv
touch ./results/stage3/visited.csv
touch ./results/stage3/status_stack.csv
touch ./results/stage3/status_tree.csv
touch ./results/stage3/status_native.csv
CURRENT_CRATE=""
TIMEOUT=10m
TIMEOUT_MIRI=5m

MEMORY_MODE="-Zmiri-llvm-read-uninit"
if [ "$2" == "-z" ]; then
    MEMORY_MODE="-Zmiri-llvm-zero-init"
fi

rustup default mirilli

while IFS=, read -r test_name crate_name version <&3;
do
    SUCCEEDED_DOWNLOADING=0
    if [ "$CURRENT_CRATE" == "" ] || [ "$crate_name" != "$CURRENT_CRATE" ]; then
        rm -rf ./extracted
        TRIES_REMAINING=3
        while [ "$TRIES_REMAINING" -gt "0" ]; do
            echo "Downloading $crate_name@$version..."
            ./scripts/misc/cargo-download.sh "$crate_name" "$version"
            EXITCODE=$?
            TRIES_REMAINING=$(( TRIES_REMAINING - 1 ))
            if [ "$EXITCODE" -eq "0" ]; then
                echo "$crate_name,$version" >> ./results/stage3/visited.csv
                TRIES_REMAINING=0
                SUCCEEDED_DOWNLOADING=1
            else
                echo "FAILED (exit $EXITCODE)"
                if [ "$TRIES_REMAINING" -eq "0" ]; then
                    echo "$crate_name,$version,$EXITCODE" >> "./results/stage3/failed_download.csv"
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
    if [ "$SUCCEEDED_DOWNLOADING" -eq "1" ]; then

        CURRENT_CRATE="$crate_name"
        mkdir -p ./results/stage3/crates/"$crate_name"/
        cd ./extracted || exit

        echo "Compiling rustc test binary..."
        RUSTC_COMP_EXITCODE=1
        OUTPUT=$(timeout $TIMEOUT cargo test --tests -- --list 2> err)
        RUSTC_COMP_EXITCODE=$?
        echo "Exit: $RUSTC_COMP_EXITCODE"
        echo "$RUSTC_COMP_EXITCODE,$crate_name,\"$test_name\"" >> ../results/stage3/status_native_comp.csv
        
        if [ "$RUSTC_COMP_EXITCODE" -eq 0 ]; then

            echo "Executing rustc test $test_name..."
            RUSTC_EXEC_EXITCODE=1
            OUTPUT=$(timeout $TIMEOUT cargo test -q "$test_name" -- --exact 2> err)
            RUSTC_EXEC_EXITCODE=$?
            echo "Exit: $RUSTC_EXEC_EXITCODE"
            mkdir -p "../results/stage3/crates/$crate_name/native"
            cp err "../results/stage3/crates/$crate_name/native/$test_name.err.log"
            echo "$OUTPUT" > "../results/stage3/crates/$crate_name/native/$test_name.out.log"
            rm err
            echo "$RUSTC_EXEC_EXITCODE,$crate_name,\"$test_name\"" >> ../results/stage3/status_native.csv

            if [ ! -f "./$crate_name.sum.bc" ]; then
                echo "Assembling bytecode files..."
                cp /usr/src/mirilli/libcxx.bc ./libcxx.bc
                rllvm-as "./$crate_name.sum.bc"
                RLLVM_AS_EXITCODE=$?
                echo "Exit: $RLLVM_AS_EXITCODE"    
                if [ "$RLLVM_AS_EXITCODE" -ne 0 ]; then
                    exit 1
                fi
                if [ ! -f "../results/stage3/crates/$crate_name/llvm_bc.csv" ]; then
                    cp ./llvm_bc.csv ../results/stage3/crates/"$crate_name"/
                fi
            fi

            echo "Compiling miri test binary..."
            MIRI_COMP_EXITCODE=1
            OUTPUT=$(MIRIFLAGS="-Zmiri-disable-bc" timeout $TIMEOUT cargo miri test --tests -- --list 2> err)
            MIRI_COMP_EXITCODE=$?
            echo "Exit: $MIRI_COMP_EXITCODE"
            echo "$MIRI_COMP_EXITCODE,$crate_name,\"$test_name\"" >> ../results/stage3/status_miri_comp.csv
            if [ ! -f "../results/stage3/crates/$crate_name/miri.comp.log" ]; then
                cp err ../results/stage3/crates/$crate_name/miri.comp.log
            fi
            if [ "$MIRI_COMP_EXITCODE" -eq 0 ]; then
                MFLAGS="$MEMORY_MODE -Zmiri-descriptive-ub -Zmiri-backtrace=full -Zmiri-symbolic-alignment-check -Zmiri-llvm-alignment-check-rust-only -Zmiri-disable-isolation -Zmiri-llvm-log -Zmiri-extern-bc-file=./$crate_name.sum.bc"
                echo "Executing Miri in Stacked Borrows mode..."
                dmesg -T | egrep -i 'killed process' > ./prev_log.txt
                MIRI_STACK_EXITCODE=1
                OUTPUT=$(RUST_BACKTRACE=1 MIRI_BACKTRACE=1 MIRIFLAGS="$MFLAGS" timeout $TIMEOUT_MIRI cargo miri test -q "$test_name" -- --exact 2> err)
                MIRI_STACK_EXITCODE=$?
                dmesg -T | egrep -i 'killed process' > ./after_log.txt

                echo "Exit: $MIRI_STACK_EXITCODE"
                echo "$MIRI_STACK_EXITCODE,$crate_name,\"$test_name\"" >> ../results/stage3/status_stack.csv
                mkdir -p "../results/stage3/crates/$crate_name/stack"
                cp err "../results/stage3/crates/$crate_name/stack/$test_name.err.log"
                comm -1 -3 ./prev_log.txt ./after_log.txt > "../results/stage3/crates/$crate_name/stack/$test_name.sys.log"
                echo "$OUTPUT" > "../results/stage3/crates/$crate_name/stack/$test_name.out.log"
                
                rm err
                rm ./prev_log.txt
                rm ./after_log.txt

                if [ -f "./llvm_flags.csv" ]; then
                    mv ./llvm_flags.csv "$test_name".flags.csv
                    cp "$test_name".flags.csv ../results/stage3/crates/"$crate_name"/stack/
                fi
                if [ -f "./llvm_conversions.csv" ]; then
                    mv ./llvm_conversions.csv "$test_name".convert.csv
                    cp "$test_name".convert.csv ../results/stage3/crates/"$crate_name"/stack/
                fi
                echo "Executing Miri in Tree Borrows mode..."
                dmesg -T | egrep -i 'killed process' > ./prev_log.txt
                MIRI_TREE_EXITCODE=1
                OUTPUT=$(RUST_BACKTRACE=1 MIRI_BACKTRACE=1 MIRIFLAGS="$MFLAGS -Zmiri-tree-borrows -Zmiri-unique-is-unique" timeout $TIMEOUT_MIRI cargo miri test -q "$test_name" -- --exact 2> err)
                MIRI_TREE_EXITCODE=$?
                dmesg -T | egrep -i 'killed process' > ./after_log.txt

                echo "Exit: $MIRI_TREE_EXITCODE"
                echo "$MIRI_TREE_EXITCODE,$crate_name,\"$test_name\"" >> ../results/stage3/status_tree.csv
                mkdir -p "../results/stage3/crates/$crate_name/tree"
                cp err "../results/stage3/crates/$crate_name/tree/$test_name.err.log"
                echo "$OUTPUT" > "../results/stage3/crates/$crate_name/tree/$test_name.out.log"
                comm -1 -3 ./prev_log.txt ./after_log.txt > "../results/stage3/crates/$crate_name/tree/$test_name.sys.log"

                rm err
                rm ./prev_log.txt
                rm ./after_log.txt

                if [ -f "./llvm_flags.csv" ]; then
                    mv "./llvm_flags.csv" "$test_name".flags.csv
                    cp "$test_name".flags.csv ../results/stage3/crates/"$crate_name"/tree/
                fi
                if [ -f "./llvm_conversions.csv" ]; then
                    mv ./llvm_conversions.csv "$test_name".convert.csv
                    cp "$test_name".convert.csv ../results/stage3/crates/"$crate_name"/tree/
                fi
            fi
        fi
        cd ..
    else
        CURRENT_CRATE=""
    fi
done 3<"$1"
