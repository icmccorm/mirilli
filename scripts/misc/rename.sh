# rename all files in a folder to "[index].csv", where index begins at 1
# and increments by 1 for each file in the folder

DIR=$1
INDEX=1
for FILE in $DIR/*; do
    mv $FILE $DIR/$INDEX.csv
    INDEX=$((INDEX+1))
done