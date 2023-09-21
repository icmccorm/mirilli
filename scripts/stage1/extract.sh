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
touch ./data/results/has_bytecode.csv
for file in $1/*.zip; do
    unzip -q "$file" -d ./temp
    filename=$(basename -- "$file")
    filename="${filename%.*}"
    if [ -d "./temp/$filename" ]; then
        ROOT="./temp/$filename"
    else
        ROOT="./temp/results"
    fi
    echo $file
    wc -l $ROOT/visited.csv
    cp -r $ROOT/early/* ./data/results/early
    cp -r $ROOT/late/* ./data/results/late
    cat $ROOT/failed_compilation.csv >> ./data/results/failed_compilation.csv
    cat $ROOT/failed_download.csv >> ./data/results/failed_download.csv
    cat $ROOT/visited.csv >> ./data/results/visited.csv
    cat $ROOT/has_bytecode.csv >> ./data/results/has_bytecode.csv
    tail -n +2 $ROOT/count.csv >> ./data/results/count.csv
    rm -rf ./temp
done