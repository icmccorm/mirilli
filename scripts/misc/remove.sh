#!/bin/bash
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <root_directory> <text_file>"
    exit 1
fi
root_directory=$1
text_file=$2
while IFS= read -r line
do
    file_path="$root_directory/$line"
    rm -f "$file_path"
done < "$text_file"
