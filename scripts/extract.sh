echo "Preparing directories..."
rm -rf ./data/results
rm -rf ./temp
mkdir ./data/results
mkdir ./data/results/late
mkdir ./data/results/early
mkdir ./data/results/tests
touch ./data/results/count.csv
touch ./data/results/failed_compilation.csv
touch ./data/results/failed_download.csv
touch ./data/results/visited.csv
touch ./data/results/tests/visited.csv
touch ./data/results/tests/failed_download.csv
touch ./data/results/tests/failed_miri_compilation.csv
touch ./data/results/tests/failed_rustc_compilation.csv
touch ./data/results/tests/tests.csv
echo "exit_code,had_ffi,test_name,crate_name,version" >> ./data/results/tests/tests.csv
echo "crate_name,version,exit_code" >> ./data/results/tests/failed_miri_compilation.csv
echo "crate_name,version,exit_code" >> ./data/results/tests/failed_rustc_compilation.csv
for file in ./data/archives/partitions/crates/*.zip; do
    unzip -q "$file" -d ./temp
    filename=$(basename -- "$file")
    filename="${filename%.*}"
    if [ -d "./temp/$filename" ]; then
        ROOT="./temp/$filename"
    else
        ROOT="./temp/results"
    fi
    echo $ROOT
    cp -r $ROOT/early/* ./data/results/early
    cp -r $ROOT/late/* ./data/results/late
    cat $ROOT/failed_compilation.csv >> ./data/results/failed_compilation.csv
    cat $ROOT/failed_download.csv >> ./data/results/failed_download.csv
    cat $ROOT/visited.csv >> ./data/results/visited.csv
    tail -n +2 $ROOT/count.csv >> ./data/results/count.csv
    rm -rf ./temp
done
RESULT_DIR=./data/results/tests
for file in ./data/archives/partitions/ffi/*.zip; do
    unzip -q "$file" -d ./temp
    ROOT="./temp/tests"
    for csv_file in $ROOT/info/*.csv; do
        filename=$(basename -- "$csv_file")
        filename="${filename%.*}"   
        PATTERN="(.*)-([0-9]+\.[0-9]+\.[0-9]+.*)"
        if [[ $filename =~ $PATTERN ]]; then
            crate_name="${BASH_REMATCH[1]}"
            version="${BASH_REMATCH[2]}"
        else
            echo "INVALID CRATE VERSION: $filename"
            exit 1
        fi
        while read -r line; do
            echo "$line,$crate_name,$version" >> $RESULT_DIR/tests.csv
        done < $csv_file
    done
    cat $ROOT/visited.csv >> $RESULT_DIR/visited.csv
    cat $ROOT/failed_download.csv >> $RESULT_DIR/failed_download.csv
    cat $ROOT/failed_miri_compilation.csv >> $RESULT_DIR/failed_miri_compilation.csv
    cat $ROOT/failed_rustc_compilation.csv >> $RESULT_DIR/failed_rustc_compilation.csv
    rm -rf ./temp
done