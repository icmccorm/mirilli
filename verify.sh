
RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m'
make clean && make all
mkdir -p "$2/$1"
mkdir -p "$2/$1/early"
mkdir -p "$2/$1/late"
TO_VISIT=""
if test -f "$2/$1/visited.csv"; then
    TO_VISIT=$(comm -23 "./data/partitions/partition$1.csv" "$2/$1/visited.csv")
else
    TO_VISIT=$(cat ./data/partitions/partition$1.csv)
fi
while IFS=, read name version; 
do 
    if (cargo-download -x "$name==$version" --output ./test 1> /dev/null); then 
        if ! (cd test && cargo dylint --all); then
            echo "$name,$version" >> "$2/$1/failed.csv"
        fi
        echo "$name,$version" >> "$2/$1/visited.csv"
        [ ! -f ./test/ffickle_early.json ] || mv ./test/ffickle_early.json "$2/$1/early/$name.json"
        [ ! -f ./test/ffickle_late.json ] || mv ./test/ffickle_late.json "$2/$1/late/$name.json"
    else
        echo "${RED}DOWNLOAD FAILED${NC} $name\n"
    fi
    rm -rf ./test
done <<< "$TO_VISIT"
echo "${GREEN}FINISHED!${NC} $name\n"