#!/bin/bash

echo "Preparing directories..."
rm -rf ./results/stage2
rm -rf ./temp

RESULT_DIR=./results/stage2
mkdir -p "$RESULT_DIR"
mkdir "$RESULT_DIR/info"
mkdir "$RESULT_DIR/logs"
touch "$RESULT_DIR/visited.csv"
touch "$RESULT_DIR/failed_download.csv"
touch "$RESULT_DIR/status_miri_comp.csv"
touch "$RESULT_DIR/status_rustc_comp.csv"
touch "$RESULT_DIR/tests.csv"

RESULT_DIR=./results/stage2
for file in "$1"/*.zip; do
    unzip -q "$file"
    ROOT="./results/stage2"
    echo "$file"
    FILES=$(find "$ROOT/info/" -name "*.csv")
    for csv_file in $FILES; do
        echo "$csv_file"
        filename=$(basename -- "$csv_file")
        filename="${filename%.*}"   
        while read -r line; do
            echo "$line,$filename" >> $RESULT_DIR/tests.csv
        done < "$csv_file"
    done
    cat $ROOT/visited.csv >> $RESULT_DIR/visited.csv
    cat $ROOT/failed_download.csv >> $RESULT_DIR/failed_download.csv
    cat $ROOT/status_miri_comp.csv >> $RESULT_DIR/status_miri_comp.csv
    cat $ROOT/status_rustc_comp.csv >> $RESULT_DIR/status_rustc_comp.csv
    cp -r $ROOT/logs/* $RESULT_DIR/logs
    rm -rf ./results
done