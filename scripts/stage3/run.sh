#!/bin/bash
HELPTEXT="
Usage: ./run.sh <DIR> <stage3.csv> <"-z" (optional)>

The purpose of this script is to execute each of the tests discovered
in Stage 2 with MiriLLI to find cross-language bugs.

This takes as input the CSV file "stage3.csv," which is produced as 
by compiling the output from Stage 2.

The third argument is optional, and must be "-z" if provided. This
will enable the "Zeroed" mode in MiriLLI, which zero-initializes all
LLVM-allocated memory by default. If this is enabled, then results will
be stored in the directory <DIR>/stage3/zeroed. Otherwise, results will
be stored in <DIR>/stage3/uninit. Existing results will be overwritten.

Additional details are documented in DATASET.md
"

if [ "$#" -lt 2 ]; then
    echo "$HELPTEXT"
    exit 1
fi
if [ ! -f $2 ]; then
    echo "Unable to locate list of candidate crates."
    exit 1
fi

DIR=$1
STAGE3_DIR=$DIR/stage3

export PATH="$HOME/.cargo/bin:$PATH"
export DEFAULT_FLAGS="-g -O0 --save-temps=obj"
export CC="clang-16 $DEFAULT_FLAGS"
export CXX="clang++-16 $DEFAULT_FLAGS"

CURRENT_CRATE=""
TIMEOUT=10m
TIMEOUT_MIRI=5m
MEMORY_MODE=""
if [ "$3" == "-z" ]; then
    MEMORY_MODE="-Zmiri-llvm-memory-zeroed"
    STAGE3_DIR="$STAGE3_DIR/zeroed"
else
    STAGE3_DIR="$STAGE3_DIR/uninit"
fi

rm -rf $STAGE3_DIR
rm -rf ./extracted
mkdir -p $STAGE3_DIR
mkdir -p $STAGE3_DIR/crates


touch $STAGE3_DIR/visited.csv
touch $STAGE3_DIR/status_download.csv
touch $STAGE3_DIR/status_native_comp.csv
touch $STAGE3_DIR/status_miri_comp.csv
touch $STAGE3_DIR/status_stack.csv
touch $STAGE3_DIR/status_tree.csv
touch $STAGE3_DIR/status_native.csv

CRATE_COLNAMES="crate_name,version"
STATUS_COLNAMES="exit_code,crate_name,test_name"

echo "$CRATE_COLNAMES" >  $STAGE3_DIR/visited.csv
echo "$STATUS_COLNAMES" > $STAGE3_DIR/status_miri_comp.csv
echo "$STATUS_COLNAMES" > $STAGE3_DIR/status_native_comp.csv
echo "$STATUS_COLNAMES" > $STAGE3_DIR/status_download.csv
echo "$STATUS_COLNAMES" > $STAGE3_DIR/status_native.csv
echo "$STATUS_COLNAMES" > $STAGE3_DIR/status_stack.csv
echo "$STATUS_COLNAMES" > $STAGE3_DIR/status_tree.csv

rustup override set mirilli
SETUP=0

while IFS=, read -r test_name crate_name version <&3;
do
    SUCCEEDED_DOWNLOADING=0
    if [ "$CURRENT_CRATE" == "" ] || [ "$crate_name" != "$CURRENT_CRATE" ]; then
        rm -rf ./extracted
        TRIES_REMAINING=3
        while [ "$TRIES_REMAINING" -gt "0" ]; do
            echo "Downloading $crate_name@$version..."
            (cargo-download "$crate_name==$version" -x -o extracted)
            EXITCODE=$?
            TRIES_REMAINING=$(( TRIES_REMAINING - 1 ))
            if [ "$EXITCODE" -eq "0" ]; then
                echo "$crate_name,$version" >> $STAGE3_DIR/visited.csv
                TRIES_REMAINING=0
                SUCCEEDED_DOWNLOADING=1
            else
                echo "FAILED (exit $EXITCODE)"
                if [ "$TRIES_REMAINING" -eq "0" ]; then
                    echo "$crate_name,$version,$EXITCODE" >> "$STAGE3_DIR/status_download.csv"
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
        mkdir -p $STAGE3_DIR/crates/"$crate_name"/
        cd ./extracted || exit
        if [ "$SETUP" -eq 0 ]; then
            cargo miri clean 
            cargo miri setup
            SETUP=1
        fi
        echo "Compiling rustc test binary..."
        RUSTC_COMP_EXITCODE=1
        OUTPUT=$(timeout $TIMEOUT cargo test --tests -- --list 2> err)
        RUSTC_COMP_EXITCODE=$?
        echo "Exit: $RUSTC_COMP_EXITCODE"
        echo "$RUSTC_COMP_EXITCODE,$crate_name,\"$test_name\"" >> ../$STAGE3_DIR/status_native_comp.csv
        
        if [ "$RUSTC_COMP_EXITCODE" -eq 0 ]; then

            echo "Executing rustc test $test_name..."
            RUSTC_EXEC_EXITCODE=1
            OUTPUT=$(timeout $TIMEOUT cargo test -q "$test_name" -- --exact 2> err)
            RUSTC_EXEC_EXITCODE=$?
            echo "Exit: $RUSTC_EXEC_EXITCODE"
            mkdir -p "../$STAGE3_DIR/crates/$crate_name/native"
            cp err "../$STAGE3_DIR/crates/$crate_name/native/$test_name.err.log"
            echo "$OUTPUT" > "../$STAGE3_DIR/crates/$crate_name/native/$test_name.out.log"
            rm err
            echo "$RUSTC_EXEC_EXITCODE,$crate_name,\"$test_name\"" >> ../$STAGE3_DIR/status_native.csv

            if [ ! -f "./$crate_name.sum.bc" ]; then
                echo "Assembling bytecode files..."
                rllvm-as "./$crate_name.sum.bc"
                RLLVM_AS_EXITCODE=$?
                echo "Exit: $RLLVM_AS_EXITCODE"    
                if [ "$RLLVM_AS_EXITCODE" -ne 0 ]; then
                    exit 1
                fi
                if [ ! -f "../$STAGE3_DIR/crates/$crate_name/llvm_bc.csv" ]; then
                    cp ./llvm_bc.csv ../$STAGE3_DIR/crates/"$crate_name"/
                fi
            fi

            echo "Compiling miri test binary..."
            MIRI_COMP_EXITCODE=1
            OUTPUT=$(MIRIFLAGS="-Zmiri-disable-bc" timeout $TIMEOUT cargo miri test --tests -- --list 2> err)
            MIRI_COMP_EXITCODE=$?
            echo "Exit: $MIRI_COMP_EXITCODE"
            echo "$MIRI_COMP_EXITCODE,$crate_name,\"$test_name\"" >> ../$STAGE3_DIR/status_miri_comp.csv
            if [ ! -f "../$STAGE3_DIR/crates/$crate_name/miri.comp.log" ]; then
                cp err ../$STAGE3_DIR/crates/$crate_name/miri.comp.log
            fi
            if [ "$MIRI_COMP_EXITCODE" -eq 0 ]; then
                MFLAGS="$MEMORY_MODE -Zmiri-descriptive-ub -Zmiri-backtrace=full -Zmiri-symbolic-alignment-check -Zmiri-disable-isolation -Zmiri-extern-bc-file=./$crate_name.sum.bc -Zmiri-llvm-log"
                echo "Executing Miri in Stacked Borrows mode..."
                MIRI_STACK_EXITCODE=1
                OUTPUT=$(RUST_BACKTRACE=1 MIRI_BACKTRACE=1 MIRIFLAGS="$MFLAGS" timeout $TIMEOUT_MIRI cargo miri test -q "$test_name" -- --exact 2> err)
                MIRI_STACK_EXITCODE=$?

                echo "Exit: $MIRI_STACK_EXITCODE"
                echo "$MIRI_STACK_EXITCODE,$crate_name,\"$test_name\"" >> ../$STAGE3_DIR/status_stack.csv
                mkdir -p "../$STAGE3_DIR/crates/$crate_name/stack"
                cp err "../$STAGE3_DIR/crates/$crate_name/stack/$test_name.err.log"
                echo "$OUTPUT" > "../$STAGE3_DIR/crates/$crate_name/stack/$test_name.out.log"
                
                rm err

                if [ -f "./llvm_flags.csv" ]; then
                    mv ./llvm_flags.csv "$test_name".flags.csv
                    cp "$test_name".flags.csv ../$STAGE3_DIR/crates/"$crate_name"/stack/
                fi
                if [ -f "./llvm_conversions.csv" ]; then
                    mv ./llvm_conversions.csv "$test_name".convert.csv
                    cp "$test_name".convert.csv ../$STAGE3_DIR/crates/"$crate_name"/stack/
                fi
                echo "Executing Miri in Tree Borrows mode..."
                MIRI_TREE_EXITCODE=1
                OUTPUT=$(RUST_BACKTRACE=1 MIRI_BACKTRACE=1 MIRIFLAGS="$MFLAGS -Zmiri-tree-borrows -Zmiri-unique-is-unique" timeout $TIMEOUT_MIRI cargo miri test -q "$test_name" -- --exact 2> err)
                MIRI_TREE_EXITCODE=$?

                echo "Exit: $MIRI_TREE_EXITCODE"
                echo "$MIRI_TREE_EXITCODE,$crate_name,\"$test_name\"" >> ../$STAGE3_DIR/status_tree.csv
                mkdir -p "../$STAGE3_DIR/crates/$crate_name/tree"
                cp err "../$STAGE3_DIR/crates/$crate_name/tree/$test_name.err.log"
                echo "$OUTPUT" > "../$STAGE3_DIR/crates/$crate_name/tree/$test_name.out.log"

                rm err

                if [ -f "./llvm_flags.csv" ]; then
                    mv "./llvm_flags.csv" "$test_name".flags.csv
                    cp "$test_name".flags.csv ../$STAGE3_DIR/crates/"$crate_name"/tree/
                fi
                if [ -f "./llvm_conversions.csv" ]; then
                    mv ./llvm_conversions.csv "$test_name".convert.csv
                    cp "$test_name".convert.csv ../$STAGE3_DIR/crates/"$crate_name"/tree/
                fi
            fi
        fi
        cd ..
    else
        CURRENT_CRATE=""
    fi
done 3<"$2"

printf 'FINISHED!\n'