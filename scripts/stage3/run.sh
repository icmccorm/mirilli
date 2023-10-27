#!/bin/bash
export PATH="$HOME/.cargo/bin:$PATH"
export DEFAULT_FLAGS="-g -O0 --save-temps=obj"
export CC="clang-16 $DEFAULT_FLAGS"
export CXX="clang++-16 $DEFAULT_FLAGS"
rm -rf ./data/results/stage3
rm -rf ./extracted
mkdir -p ./data/results/stage3
mkdir -p ./data/results/stage3/crates
touch ./data/results/stage3/failed_download.csv
touch ./data/results/stage3/status_native_comp.csv
touch ./data/results/stage3/status_miri_comp.csv
touch ./data/results/stage3/visited.csv
touch ./data/results/stage3/status_stack.csv
touch ./data/results/stage3/status_tree.csv
touch ./data/results/stage3/status_native.csv
CURRENT_CRATE=""
TIMEOUT=10m
TIMEOUT_MIRI=3m
# if $2 is equal to -v, then set LOGGING_FLAG to -Zmiri-llvm-log-verbose. If not, set it to -Zmiri-llvm-log
if [ "$2" == "-v" ]; then
    LOGGING_FLAG="-Zmiri-llvm-log-verbose"
else
    LOGGING_FLAG="-Zmiri-llvm-log"
fi

while IFS=, read -r test_name crate_name version <&3;
do
    SUCCEEDED_DOWNLOADING=0
    if [ "$CURRENT_CRATE" == "" ] || [ "$crate_name" != "$CURRENT_CRATE" ]; then
        rm -rf ./extracted
        TRIES_REMAINING=3
        while [ "$TRIES_REMAINING" -gt "0" ]; do
            echo "Downloading $crate_name@$version..."
            cargo-download -x "$crate_name==$version" --output ./extracted
            EXITCODE=$?
            TRIES_REMAINING=$(( TRIES_REMAINING - 1 ))
            if [ "$EXITCODE" -eq "0" ]; then
                echo "$crate_name,$version" >> ./data/results/stage3/visited.csv
                TRIES_REMAINING=0
                SUCCEEDED_DOWNLOADING=1
            else
                echo "FAILED (exit $EXITCODE)"
                if [ "$TRIES_REMAINING" -eq "0" ]; then
                    echo "$crate_name,$version,$EXITCODE" >> "./data/results/stage3/failed_download.csv"
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
        mkdir -p ./data/results/stage3/crates/"$crate_name"/
        cd ./extracted || exit

        echo "Compiling rustc test binary..."
        RUSTC_COMP_EXITCODE=0
        OUTPUT=$(timeout $TIMEOUT cargo test --tests -- --list 2> err)
        RUSTC_COMP_EXITCODE=$?
        echo "Exit: $RUSTC_COMP_EXITCODE"
        echo "$RUSTC_COMP_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/stage3/status_native_comp.csv
        
        if [ "$RUSTC_COMP_EXITCODE" -eq 0 ]; then

            echo "Executing rustc test $test_name..."
            RUSTC_EXEC_EXITCODE=0
            OUTPUT=$(timeout $TIMEOUT cargo test -q "$test_name" -- --exact 2> err)
            RUSTC_EXEC_EXITCODE=$?
            echo "Exit: $RUSTC_EXEC_EXITCODE"
            mkdir -p "../data/results/stage3/crates/$crate_name/native"
            cp err "../data/results/stage3/crates/$crate_name/native/$test_name.err.log"
            echo "$OUTPUT" > "../data/results/stage3/crates/$crate_name/native/$test_name.out.log"
            rm err
            echo "$RUSTC_EXEC_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/stage3/status_native.csv

            if [ ! -f "./$crate_name.sum.bc" ]; then
                echo "Assembling bytecode files..."
                rllvm-as "./$crate_name.sum.bc"
                RLLVM_AS_EXITCODE=$?
                echo "Exit: $RLLVM_AS_EXITCODE"    
                if [ "$RLLVM_AS_EXITCODE" -ne 0 ]; then
                    exit 1
                fi
                if [ ! -f "../data/results/stage3/crates/$crate_name/llvm_bc.csv" ]; then
                    cp ./llvm_bc.csv ../data/results/stage3/crates/"$crate_name"/
                fi
            fi

            echo "Compiling miri test binary..."
            MIRI_COMP_EXITCODE=0
            OUTPUT=$(timeout $TIMEOUT cargo miri test --tests -- --list 2> err)
            MIRI_COMP_EXITCODE=$?
            echo "Exit: $MIRI_COMP_EXITCODE"
            echo "$MIRI_COMP_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/stage3/status_miri_comp.csv
            if [ "$MIRI_COMP_EXITCODE" -eq 0 ]; then
                MFLAGS="-Zmiri-symbolic-alignment-check -Zmiri-disable-isolation $LOGGING_FLAG -Zmiri-extern-bc-file=./$crate_name.sum.bc"
                echo "Executing Miri in Stacked Borrows mode..."
                MIRI_STACK_EXITCODE=0
                OUTPUT=$(MIRIFLAGS="$MFLAGS" timeout $TIMEOUT_MIRI cargo miri test -q "$test_name" -- --exact 2> err)
                MIRI_STACK_EXITCODE=$?
                echo "Exit: $MIRI_STACK_EXITCODE"
                echo "$MIRI_STACK_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/stage3/status_stack.csv
                mkdir -p "../data/results/stage3/crates/$crate_name/stack"
                cp err "../data/results/stage3/crates/$crate_name/stack/$test_name.err.log"
                echo "$OUTPUT" > "../data/results/stage3/crates/$crate_name/stack/$test_name.out.log"
                rm err
                if [ -f "./flags.json" ]; then
                    mv ./flags.json "$test_name".json
                    cp "$test_name".json ../data/results/stage3/crates/"$crate_name"/stack/
                fi
                if [ -f "./llvm_conversions.csv" ]; then
                    mv ./llvm_conversions.csv "$test_name".convert.csv
                    cp "$test_name".convert.csv ../data/results/stage3/crates/"$crate_name"/stack/
                fi
                if [ -f "./llvm_upcasts.csv" ]; then
                    mv ./llvm_upcasts.csv "$test_name".upcast.csv
                    cp "$test_name".upcast.csv ../data/results/stage3/crates/"$crate_name"/stack/
                fi
                echo "Executing Miri in Tree Borrows mode..."
                MIRI_TREE_EXITCODE=0
                OUTPUT=$(MIRIFLAGS="$MFLAGS -Zmiri-tree-borrows" timeout $TIMEOUT_MIRI cargo miri test -q "$test_name" -- --exact 2> err)
                MIRI_TREE_EXITCODE=$?
                echo "Exit: $MIRI_TREE_EXITCODE"
                echo "$MIRI_TREE_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/stage3/status_tree.csv
                mkdir -p "../data/results/stage3/crates/$crate_name/tree"
                cp err "../data/results/stage3/crates/$crate_name/tree/$test_name.err.log"
                echo "$OUTPUT" > "../data/results/stage3/crates/$crate_name/tree/$test_name.out.log"
                rm err
                if [ -f "./flags.json" ]; then
                    mv ./flags.json "$test_name".json
                    cp "$test_name".json ../data/results/stage3/crates/"$crate_name"/tree/
                fi
                if [ -f "./llvm_conversions.csv" ]; then
                    mv ./llvm_conversions.csv "$test_name".convert.csv
                    cp "$test_name".convert.csv ../data/results/stage3/crates/"$crate_name"/tree/
                fi
                if [ -f "./llvm_upcasts.csv" ]; then
                    mv ./llvm_upcasts.csv "$test_name".upcast.csv
                    cp "$test_name".upcast.csv ../data/results/stage3/crates/"$crate_name"/tree/
                fi
            fi
        fi
        cd ..
    else
        CURRENT_CRATE=""
    fi
done 3<"$1"