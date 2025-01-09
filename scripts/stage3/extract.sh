#!/bin/bash
if [ "$#" -ne 2 ]; then
    echo "Usage: ./extract.sh <path to output directory> <path to stage3 results>"
    exit 1
fi
RESULT_DIR=$2
if [ -d "$RESULT_DIR" ]; then
    rm -rf "$RESULT_DIR"
fi
mkdir "$RESULT_DIR"
touch "$RESULT_DIR"/visited.csv
touch "$RESULT_DIR"/status_download.csv
touch "$RESULT_DIR"/status_native_comp.csv
touch "$RESULT_DIR"/status_miri_comp.csv
touch "$RESULT_DIR"/status_stack.csv
touch "$RESULT_DIR"/status_tree.csv
touch "$RESULT_DIR"/status_native.csv
for FILE in "$2"/*.zip; do
    echo "Unzipping $FILE..."
    unzip -q "$FILE"
    ROOT="./stage3"  
    for CRATE_DIR in "$ROOT"/crates/*; do
        echo "Visiting $CRATE_DIR..."
        CRATE_NAME=$(basename "$CRATE_DIR")
        mkdir -p "$RESULT_DIR/crates/$CRATE_NAME/"
        mkdir -p "$RESULT_DIR/crates/$CRATE_NAME/tree/"
        mkdir -p "$RESULT_DIR/crates/$CRATE_NAME/stack/"
        if [ -d "$ROOT/crates/$CRATE_NAME/tree" ]; then
            if [ "$(ls -A "$ROOT/crates/$CRATE_NAME/tree")" ]; then
                cp -rf $ROOT/crates/"$CRATE_NAME"/tree/* $RESULT_DIR/crates/"$CRATE_NAME"/tree/
            fi
        fi
        if [ -d "$ROOT/crates/$CRATE_NAME/stack" ]; then
            if [ "$(ls -A "$ROOT/crates/$CRATE_NAME/stack")" ]; then
                cp -rf $ROOT/crates/"$CRATE_NAME"/stack/* $RESULT_DIR/crates/"$CRATE_NAME"/stack/
            fi
        fi
        if [ ! -f "$RESULT_DIR/crates/$CRATE_NAME/llvm_bc.csv" ] && [ -f "$ROOT/crates/$CRATE_NAME/llvm_bc.csv" ]; then
            cp -rf $ROOT/crates/"$CRATE_NAME"/llvm_bc.csv $RESULT_DIR/crates/"$CRATE_NAME"/llvm_bc.csv
        fi
    done
    cat $ROOT/status_download.csv >> "$RESULT_DIR/status_download.csv"
    cat $ROOT/status_native_comp.csv >> "$RESULT_DIR/status_native_comp.csv"
    cat $ROOT/status_miri_comp.csv >> "$RESULT_DIR/status_miri_comp.csv"
    cat $ROOT/status_stack.csv >> "$RESULT_DIR/status_stack.csv"
    cat $ROOT/status_tree.csv >> "$RESULT_DIR/status_tree.csv"
    cat $ROOT/status_native.csv >> "$RESULT_DIR/status_native.csv"
    cat $ROOT/visited.csv >> "$RESULT_DIR/visited.csv"
    rm -rf ./home
done
