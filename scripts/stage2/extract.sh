#!/bin/bash
HELPTEXT="Usage: ./extract.sh <path to stage1 results> <path to directory containing ZIP files>"
if [ "$#" -ne 2 ]; then
    echo $HELPTEXT
    exit 1
fi
DIR="$1/stage2"
ROOT="$2/stage2"
rm -rf $DIR
rm -rf ./extracted
STATUS_RUSTC_CSV="$DIR/status_rustc_comp.csv"
STATUS_MIRI_CSV="$DIR/status_miri_comp.csv"
FAILED_DOWNLOAD_CSV="$DIR/status_download.csv"
VISITED_CSV="$DIR/visited.csv"
TESTS_CSV="$DIR/tests.csv"

mkdir -p $DIR
mkdir -p $DIR/info/
mkdir -p $DIR/logs/
touch $FAILED_DOWNLOAD_CSV
touch $STATUS_MIRI_CSV
touch $STATUS_RUSTC_CSV
touch $VISITED_CSV
touch $TESTS_CSV

CRATE_COLNAMES="crate_name,version"
STATUS_COLNAMES="$CRATE_COLNAMES,exit_code"
echo "$CRATE_COLNAMES" > $VISITED_CSV
echo "$STATUS_COLNAMES" > $STATUS_MIRI_CSV
echo "$STATUS_COLNAMES" > $STATUS_RUSTC_CSV
echo "$STATUS_COLNAMES" > $FAILED_DOWNLOAD_CSV
echo "exit_code,had_ffi,test_name,crate_name" > $TESTS_CSV

for file in "$2"/*.zip; do
    unzip -q "$file"
    echo "$file"
    FILES=$(find "$ROOT/info/" -name "*.csv")
    for csv_file in $FILES; do
        echo "$csv_file"
        filename=$(basename -- "$csv_file")
        filename="${filename%.*}"   
        while read -r line; do
            echo "$line,$filename" >> $TESTS_CSV
        done < "$csv_file"
    done
    cat $ROOT/visited.csv >> $VISITED_CSV
    cat $ROOT/status_download.csv >> $FAILED_DOWNLOAD_CSV
    cat $ROOT/status_miri_comp.csv >> $STATUS_MIRI_CSV
    cat $ROOT/status_rustc_comp.csv >> $STATUS_RUSTC_CSV
    cp -r $ROOT/logs/* $DIR/logs
    rm -rf ./results
done