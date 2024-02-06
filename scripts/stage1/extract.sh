#!/bin/bash
echo "Preparing directories..."
rm -rf ./results/stage1
rm -rf ./temp
RESULT_DIR="./results/stage1"
mkdir "$RESULT_DIR"
mkdir "$RESULT_DIR/early/"
mkdir "$RESULT_DIR/late/"
mkdir "$RESULT_DIR/tests/"
mkdir "$RESULT_DIR/bytecode/"
touch "$RESULT_DIR/failed_download.csv"
touch "$RESULT_DIR/visited.csv"
touch "$RESULT_DIR/has_bytecode.csv"
touch "$RESULT_DIR/status_comp.csv"
touch "$RESULT_DIR/status_lint.csv"

for file in "$1"/*.zip; do
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
    cat "$ROOT"/status_comp.csv >> "$RESULT_DIR/status_comp.csv"
    cat "$ROOT"/status_lint.csv >> "$RESULT_DIR/status_lint.csv"
    cat "$ROOT"/failed_download.csv >> "$RESULT_DIR/failed_download.csv"
    cat "$ROOT"/visited.csv >> "$RESULT_DIR/visited.csv"
    cat "$ROOT"/has_bytecode.csv >> "$RESULT_DIR/has_bytecode.csv"
    rm -rf ./temp
done

