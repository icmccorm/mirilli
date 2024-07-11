echo "Preparing directories..."
touch ./dataset/stage1/has_tests.csv
for file in ./dataset/stage1/tests/*.txt; do
    echo "$file"
    # get the number of lines that end in ": test"
    num_tests=$(grep -c ": test" "$file")

    # get the file name
    file_name=$(basename -- "$file")
    file_name="${file_name%.*}"

    # write the file name and number of tests to a CSV file
    echo "$file_name,$num_tests" >> ./dataset/stage1/has_tests.csv
done