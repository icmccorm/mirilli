#!/bin/bash
export PATH="$HOME/.cargo/bin:$PATH"
export CC="clang -g -O0 --save-temps=obj"
rm -rf ./data/results/execution
rm -rf ./extracted
mkdir -p ./data/results/execution
mkdir -p ./data/results/execution/crates
touch ./data/results/execution/failed_download.csv
touch ./data/results/execution/status_native_comp.csv
touch ./data/results/execution/status_miri_comp.csv
touch ./data/results/execution/visited.csv
touch ./data/results/execution/status_stack.csv
touch ./data/results/execution/status_tree.csv
touch ./data/results/execution/status_native.csv
CURRENT_CRATE=""
TIMEOUT=3m
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
                echo "$crate_name,$version" >> ./data/results/execution/visited.csv
                TRIES_REMAINING=0
                SUCCEEDED_DOWNLOADING=1
            else
                echo "FAILED (exit $EXITCODE)"
                if [ "$TRIES_REMAINING" -eq "0" ]; then
                    echo "$crate_name,$version,$EXITCODE" >> "./data/results/execution/failed_download.csv"
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
        cd ./extracted || exit

        echo "Compiling rustc test binary..."
        RUSTC_COMP_EXITCODE=0
        OUTPUT=$(timeout $TIMEOUT cargo test --tests -- --list 2> err)
        RUSTC_COMP_EXITCODE=$?
        echo "Exit: $RUSTC_COMP_EXITCODE"
        echo "$RUSTC_COMP_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/execution/status_native_comp.csv
        if [ "$RUSTC_COMP_EXITCODE" -eq 0 ]; then
            echo "Executing rustc test $test_name..."
            RUSTC_EXEC_EXITCODE=0
            OUTPUT=$(timeout $TIMEOUT cargo test -q "$test_name" -- --exact 2> err)
            RUSTC_EXEC_EXITCODE=$?
            echo "Exit: $RUSTC_EXEC_EXITCODE"
            mkdir -p "../data/results/execution/crates/$crate_name/native"
            cp err "../data/results/execution/crates/$crate_name/native/$test_name.err.log"
            echo "$OUTPUT" > "../data/results/execution/crates/$crate_name/native/$test_name.out.log"
            rm err
            echo "$RUSTC_EXEC_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/execution/status_native.csv

            echo "Compiling miri test binary..."
            MIRI_COMP_EXITCODE=0
            OUTPUT=$(timeout $TIMEOUT cargo miri test --tests -- --list 2> err)
            MIRI_COMP_EXITCODE=$?
            echo "Exit: $MIRI_COMP_EXITCODE"
            echo "$MIRI_COMP_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/execution/status_miri_comp.csv
            if [ "$MIRI_COMP_EXITCODE" -eq 0 ]; then
                echo "Executing Miri in Stacked Borrows mode..."
                MIRI_STACK_EXITCODE=0
                OUTPUT=$(MIRIFLAGS=-"Zmiri-disable-isolation -Zmiri-llvm-log" timeout $TIMEOUT cargo miri test -q "$test_name" -- --exact 2> err)
                MIRI_STACK_EXITCODE=$?
                echo "Exit: $MIRI_STACK_EXITCODE"
                echo "$MIRI_STACK_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/execution/status_stack.csv
                mkdir -p "../data/results/execution/crates/$crate_name/stack"
                cp err "../data/results/execution/crates/$crate_name/stack/$test_name.err.log"
                echo "$OUTPUT" > "../data/results/execution/crates/$crate_name/stack/$test_name.out.log"
                rm err

                mv ./llvm_calls.csv "$test_name".csv
                cp "$test_name".csv ../data/results/execution/crates/"$crate_name"/stack/
                if [ ! -f "../data/results/execution/crates/$crate_name/bc.csv" ]; then
                    cp ./llvm_bc.csv ../data/results/execution/crates/"$crate_name"/
                fi

                echo "Executing Miri in Tree Borrows mode..."
                MIRI_TREE_EXITCODE=0
                OUTPUT=$(MIRIFLAGS="-Zmiri-disable-isolation -Zmiri-tree-borrows -Zmiri-llvm-log" timeout $TIMEOUT cargo miri test -q "$test_name" -- --exact 2> err)
                MIRI_TREE_EXITCODE=$?
                echo "Exit: $MIRI_TREE_EXITCODE"
                echo "$MIRI_TREE_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/execution/status_tree.csv
                mkdir -p "../data/results/execution/crates/$crate_name/tree"
                cp err "../data/results/execution/crates/$crate_name/tree/$test_name.err.log"
                echo "$OUTPUT" > "../data/results/execution/crates/$crate_name/tree/$test_name.out.log"
                rm err

                mv ./llvm_calls.csv "$test_name".csv
                cp "$test_name".csv ../data/results/execution/crates/"$crate_name"/tree/
            fi
        fi
        cd ..
    else
        CURRENT_CRATE=""
    fi
done 3<"$1"