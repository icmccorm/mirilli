#!/bin/bash
rm -rf ./data/results
rm -rf ./results
mkdir -p ./data/results
RESULT_DIR=./data/results/execution
mkdir "$RESULT_DIR"
touch "$RESULT_DIR"/visited.csv
touch "$RESULT_DIR"/failed_download.csv
touch "$RESULT_DIR"/status_native_comp.csv
touch "$RESULT_DIR"/status_miri_comp.csv
touch "$RESULT_DIR"/status_stack.csv
touch "$RESULT_DIR"/status_tree.csv
touch "$RESULT_DIR"/status_native.csv
echo "exit_code,crate_name,test_name" >> "$RESULT_DIR"/status_native_comp.csv
echo "exit_code,crate_name,test_name" >> "$RESULT_DIR"/status_miri_comp.csv
echo "exit_code,crate_name,test_name" >> "$RESULT_DIR"/status_stack.csv
echo "exit_code,crate_name,test_name" >> "$RESULT_DIR"/status_tree.csv
echo "exit_code,crate_name,test_name" >> "$RESULT_DIR"/status_native.csv
echo "crate_name,version" >> "$RESULT_DIR"/visited.csv

for FILE in "$1"/*.zip; do
    echo "Unzipping $FILE..."
    unzip -q "$FILE"
    ROOT="./results/execution"  
    for CRATE_DIR in "$ROOT"/crates/*; do
        echo "Visiting $CRATE_DIR..."
        CRATE_NAME=$(basename "$CRATE_DIR")
        mkdir -p "$RESULT_DIR/crates/$CRATE_NAME/"
        mkdir -p "$RESULT_DIR/crates/$CRATE_NAME/tree/"
        mkdir -p "$RESULT_DIR/crates/$CRATE_NAME/stack/"
        
        if [ -d "$ROOT/crates/$CRATE_NAME/tree" ]; then
            if [ "$(ls -A "$ROOT/crates/$CRATE_NAME/tree")" ]; then
                cp -r $ROOT/crates/"$CRATE_NAME"/tree/* $RESULT_DIR/crates/"$CRATE_NAME"/tree/
            fi
        fi

        if [ -d "$ROOT/crates/$CRATE_NAME/stack" ]; then
            if [ "$(ls -A "$ROOT/crates/$CRATE_NAME/stack")" ]; then
                cp -r $ROOT/crates/"$CRATE_NAME"/stack/* $RESULT_DIR/crates/"$CRATE_NAME"/stack/
            fi
        fi

        if [ ! -f "$RESULT_DIR/crates/$CRATE_NAME/llvm_bc.csv" ] && [ -f "$ROOT/crates/$CRATE_NAME/llvm_bc.csv" ]; then
            cp -r $ROOT/crates/"$CRATE_NAME"/llvm_bc.csv $RESULT_DIR/crates/"$CRATE_NAME"/llvm_bc.csv
        fi

    done
    cat $ROOT/failed_download.csv >> "$RESULT_DIR/failed_download.csv"
    cat $ROOT/status_native_comp.csv >> "$RESULT_DIR/status_native_comp.csv"
    cat $ROOT/status_miri_comp.csv >> "$RESULT_DIR/status_miri_comp.csv"
    cat $ROOT/status_stack.csv >> "$RESULT_DIR/status_stack.csv"
    cat $ROOT/status_tree.csv >> "$RESULT_DIR/status_tree.csv"
    cat $ROOT/status_native.csv >> "$RESULT_DIR/status_native.csv"
    cat $ROOT/visited.csv >> "$RESULT_DIR/visited.csv"
    rm -rf ./results
done
