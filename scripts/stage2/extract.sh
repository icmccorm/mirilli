echo "Preparing directories..."
rm -rf ./data/results/tests
rm -rf ./temp
mkdir -p ./data/results
mkdir ./data/results/tests
touch ./data/results/tests/visited.csv
touch ./data/results/tests/failed_download.csv
touch ./data/results/tests/failed_miri_compilation.csv
touch ./data/results/tests/failed_rustc_compilation.csv
touch ./data/results/tests/tests.csv
echo "exit_code,had_ffi,test_name,crate_name" >> ./data/results/tests/tests.csv
echo "crate_name,version,exit_code" >> ./data/results/tests/failed_miri_compilation.csv
echo "crate_name,version,exit_code" >> ./data/results/tests/failed_rustc_compilation.csv
RESULT_DIR=./data/results/tests
for file in $1/*.zip; do
    unzip -q "$file"
    ROOT="./results/tests"
    echo $file
    FILES=$(find "$ROOT/info/" -name "*.csv")
    for csv_file in $FILES; do
        echo $csv_file
        filename=$(basename -- "$csv_file")
        filename="${filename%.*}"   
        while read -r line; do
            echo "$line,$filename" >> $RESULT_DIR/tests.csv
        done < $csv_file
    done
    cat $ROOT/visited.csv >> $RESULT_DIR/visited.csv
    cat $ROOT/failed_download.csv >> $RESULT_DIR/failed_download.csv
    cat $ROOT/failed_miri_compilation.csv >> $RESULT_DIR/failed_miri_compilation.csv
    cat $ROOT/failed_rustc_compilation.csv >> $RESULT_DIR/failed_rustc_compilation.csv
    rm -rf ./results
done