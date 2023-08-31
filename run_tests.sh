#!/bin/bash
export PATH="$HOME/.cargo/bin:$PATH"
export CC="clang -g -O0 --save-temps=obj"
rm -rf ./data/results/execution
rm -rf ./extracted
mkdir -p ./data/results/execution
mkdir -p ./data/results/execution/crates
touch ./data/results/execution/failed_download.csv
touch ./data/results/execution/failed_cargo_build_compilation.csv
touch ./data/results/execution/failed_cargo_test_compilation.csv
touch ./data/results/execution/failed_miri_compilation.csv
touch ./data/results/execution/failed_native_run.csv
touch ./data/results/execution/visited.csv
touch ./data/results/execution/status_stack.csv
touch ./data/results/execution/status_tree.csv
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
        cd extracted

        echo "Compiling rustc test binary..."
        RUSTC_COMP_EXITCODE=0
        OUTPUT=$(timeout $TIMEOUT cargo test -- --list 2> err)
        RUSTC_COMP_EXITCODE=$?
        echo "Exit: $RUSTC_COMP_EXITCODE"
        if [ "$RUSTC_COMP_EXITCODE" -ne 0 ]; then
            echo "$RUSTC_COMP_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/execution/failed_cargo_test_compilation.csv
            continue
        fi
        
        echo "Executing rustc test binary..."
        RUSTC_EXEC_EXITCODE=0
        OUTPUT=$(timeout $TIMEOUT cargo test -q "$test_name" -- --exact 2> err)
        RUSTC_EXEC_EXITCODE=$?
        echo "Exit: $RUSTC_EXEC_EXITCODE"
        if [ "$RUSTC_EXEC_EXITCODE" -ne 0 ]; then
            echo $err
            echo "$RUSTC_EXEC_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/execution/failed_native_run.csv
        fi

        echo "Compiling miri test binary..."
        MIRI_COMP_EXITCODE=0
        OUTPUT=$(timeout $TIMEOUT cargo miri test -- --list 2> err)
        MIRI_COMP_EXITCODE=$?
        echo "Exit: $MIRI_COMP_EXITCODE"
        if [ "$MIRI_COMP_EXITCODE" -ne 0 ]; then
            echo "$MIRI_COMP_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/execution/failed_miri_compilation.csv
            continue
        fi
        
        echo "Executing Miri in Stacked Borrows mode..."
        MIRI_STACK_EXITCODE=0
        OUTPUT=$(MIRIFLAGS=-"Zmiri-disable-isolation -Zmiri-llvm-log" timeout $TIMEOUT cargo miri test -q "$test_name" -- --exact 2> err)
        MIRI_STACK_EXITCODE=$?
        echo "Exit: $MIRI_STACK_EXITCODE"
        echo "$MIRI_STACK_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/execution/status_stack.csv
        mkdir -p "../data/results/execution/crates/$crate_name/stack"
        if [ "$MIRI_STACK_EXITCODE" -ne 0 ]; then
            if [ "$MIRI_STACK_EXITCODE" -ne 124 ]; then
                cp err "../data/results/execution/crates/$crate_name/stack/$test_name.log"
            fi
        fi

        mv ./llvm_calls.csv $test_name.csv
        cp $test_name.csv ../data/results/execution/crates/$crate_name/stack/
        if [ ! -f "../data/results/execution/crates/$crate_name/bc.csv" ]; then
            cp ./llvm_bc.csv ../data/results/execution/crates/$crate_name/
        fi

        echo "Executing Miri in Tree Borrows mode..."
        MIRI_TREE_EXITCODE=0
        OUTPUT=$(MIRI_LOG="miri::shims::llvm=debug" MIRIFLAGS="-Zmiri-disable-isolation -Zmiri-tree-borrows -Zmiri-llvm-log" timeout $TIMEOUT cargo miri test -q "$test_name" -- --exact 2> err)
        MIRI_TREE_EXITCODE=$?

        echo "Exit: $MIRI_TREE_EXITCODE"
        echo "$MIRI_TREE_EXITCODE,$crate_name,\"$test_name\"" >> ../data/results/execution/status_tree.csv
        mkdir -p "../data/results/execution/crates/$crate_name/tree"
        if [ "$MIRI_TREE_EXITCODE" -ne 0 ]; then
            if [ "$MIRI_TREE_EXITCODE" -ne 124 ]; then
                mv err "../data/results/execution/crates/$crate_name/tree/$test_name.log"
            fi
        fi
        mv ./llvm_calls.csv $test_name.csv
        cp $test_name.csv ../data/results/execution/crates/$crate_name/tree/
        cd ..
    else
        $CURRENT_CRATE=""
    fi
done 3<$1