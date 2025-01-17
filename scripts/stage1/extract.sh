#!/bin/bash
HELPTEXT="
Usage: ./extract.sh <path to stage1 results> <path to directory containing ZIP files>


"
if [ "$#" -ne 2 ]; then
    echo "$HELPTEXT"
    exit 1
fi
RESULT_DIR="$1/stage1"
echo "Preparing directories..."
rm -rf $RESULT_DIR
rm -rf ./temp
mkdir "$RESULT_DIR"
mkdir "$RESULT_DIR/early/"
mkdir "$RESULT_DIR/late/"
mkdir "$RESULT_DIR/tests/"
mkdir "$RESULT_DIR/bytecode/"


touch "$RESULT_DIR/status_download.csv"
touch "$RESULT_DIR/visited.csv"
touch "$RESULT_DIR/has_bytecode.csv"
touch "$RESULT_DIR/status_comp.csv"
touch "$RESULT_DIR/status_lint.csv"

for file in "$2"/*.zip; do
    unzip -q "$file" -d ./temp
    filename=$(basename -- "$file")
    filename="${filename%.*}"
    if [ -d "./temp/$filename" ]; then
        ROOT="./temp/$filename"
    else
        ROOT="./temp/results/stage1"
    fi
    echo "$file"
    for file in "$ROOT"/early/*; do cp "$file" "$RESULT_DIR/"; done
    for file in "$ROOT"/late/*; do cp "$file" "$RESULT_DIR/"; done
    for file in "$ROOT"/tests/*; do cp "$file" "$RESULT_DIR/"; done
    for file in "$ROOT"/bytecode/*; do cp "$file" "$RESULT_DIR/"; done
    tail -n +1 "$ROOT"/status_comp.csv >> "$RESULT_DIR/status_comp.csv"
    tail -n +1 "$ROOT"/status_lint.csv >> "$RESULT_DIR/status_lint.csv"
    tail -n +1 "$ROOT"/status_download.csv >> "$RESULT_DIR/status_download.csv"
    tail -n +1 "$ROOT"/visited.csv >> "$RESULT_DIR/visited.csv"
    tail -n +1 "$ROOT"/has_bytecode.csv >> "$RESULT_DIR/has_bytecode.csv"
    rm -rf ./temp
done

touch $RESULT_DIR/has_tests.csv
for file in $RESULT_DIR/tests/*.txt; do
    echo "$file"
    # get the number of lines that end in ": test"
    num_tests=$(grep -c ": test" "$file")

    # get the file name
    file_name=$(basename -- "$file")
    file_name="${file_name%.*}"

    # write the file name and number of tests to a CSV file
    echo "$file_name,$num_tests" >> $RESULT_DIR/has_tests.csv
done