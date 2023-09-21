rm -f ./data/results/execution/errors_stack.csv
rm -f ./data/results/execution/errors_tree.csv
rm -f ./data/results/execution/engaged_stack.csv
rm -f ./data/results/execution/engaged_tree.csv
touch ./data/results/execution/errors_stack.csv
touch ./data/results/execution/errors_tree.csv
touch ./data/results/execution/engaged_stack.csv
touch ./data/results/execution/engaged_tree.csv
RESULT_DIR=./data/results/execution
function unpack_errors() {
    ERROR_ROOT_DIR=$1
    OUTPUT_CSV=$2
    ENGAGED_CSV=$3
    echo "Parsing errors for '$ERROR_ROOT_DIR'..."
    for CRATE_DIR in "$RESULT_DIR"/crates/*; do
        CRATE_NAME=$(basename "$CRATE_DIR")
        echo "Unpacking '$1' errors for $CRATE_NAME..."
        # if the directory isn't empty
        if [ "$(ls -A "$CRATE_DIR"/"$ERROR_ROOT_DIR")" ]; then
            for LOG in "$CRATE_DIR"/"$ERROR_ROOT_DIR"/*.err.log; do
                CURR_DIR="$CRATE_DIR"/"$ERROR_ROOT_DIR"
                TEST_NAME=$(basename "$LOG" .err.log)
                CSV_NAME="$TEST_NAME".csv
                CSV_PATH="$CURR_DIR"/"$CSV_NAME"
                CSV_WC=$(cat "$CSV_PATH" | wc -l)
                
                if [ "$CSV_WC" -eq 0 ]; then
                    echo "$CRATE_NAME,\"$TEST_NAME\",0" >> $ENGAGED_CSV
                else
                    echo "$CRATE_NAME,\"$TEST_NAME\",1" >> $ENGAGED_CSV
                fi

                FATAL_RUNTIME_LINE=$(cat "$LOG" | grep -n '^fatal runtime error: stack overflow' | head -n 1)
                if [ "$FATAL_RUNTIME_LINE" != "" ]; then
                    echo "$CRATE_NAME,\"$TEST_NAME\",\"Stack Overflow\",\"\",\"\"" >> $OUTPUT_CSV
                    continue
                fi
                UNHANDLED_TYPE_LINE=$(cat "$LOG" | grep -n '^Unhandled type' | head -n 1)
                if [ "$UNHANDLED_TYPE_LINE" != "" ]; then
                    UNHANDLED_TYPE_TEXT=$(echo "$UNHANDLED_TYPE_LINE" | cut -d ':' -f 3)
                    echo "$CRATE_NAME,\"$TEST_NAME\",\"LLI Internal Error\",\"Unhandled type\",\"$UNHANDLED_TYPE_TEXT\"" >> $OUTPUT_CSV
                    continue
                fi
                LLVM_ERROR_LINE=$(cat "$LOG" | grep -n '^LLVM ERROR:' | head -n 1)
                if [ "$LLVM_ERROR_LINE" != "" ]; then
                    LLVM_ERROR_TEXT=$(echo "$LLVM_ERROR_LINE" | cut -d ':' -f 3)
                    echo "$CRATE_NAME,\"$TEST_NAME\",\"LLI Internal Error\",\"$LLVM_ERROR_TEXT\",\"\"" >> $OUTPUT_CSV
                    continue
                fi
                # check if there's a line of the form "error: could not compile [...] due to previous error"
                # if so, we can ignore the rest of the log
                PREVIOUS_ERROR_LINE=$(cat "$LOG" | grep -n '^error: could not compile' | head -n 1)
                if [ "$PREVIOUS_ERROR_LINE" != "" ]; then
                    ERROR_LINE=$(cat "$LOG" | grep -n '^error:' | head -n 1)
                    ERROR_TEXT=$(echo "$ERROR_LINE" | cut -d ':' -f 3)
                    echo "$CRATE_NAME,\"$TEST_NAME\",\"Compilation Failed\",\"$ERROR_TEXT\",\"\"" >> $OUTPUT_CSV
                    continue
                fi
                
                # find the first line that includes error, but doesn't necessarily start with it:
                # this is the first error that occurred during compilation
                ERROR_LINE=$(cat "$LOG" | grep -n '^error:' | head -n 1)
                if [ "$ERROR_LINE" != "" ]; then
                    ERROR_TYPE=$(echo "$ERROR_LINE" | cut -d ':' -f 3)
                    if [[ $ERROR_TYPE == *"unsupported operation"* ]]; then
                        ERROR_TYPE="Unsupported Operation"
                    fi
                    if [[ $ERROR_TYPE == *"test failed"* ]]; then
                        ERROR_TYPE="Test Failed"
                    fi
                    if [[ $ERROR_TYPE == *"failed to run custom build command for"* ]]; then
                        ERROR_TYPE="Custom Build Failed"
                    fi
                    if [[ $ERROR_TYPE == *"the compiler unexpectedly panicked. this is a bug."* ]]; then
                        ERROR_TYPE="Miri Internal Error"
                    fi
                    ERROR_TEXT=$(echo "$ERROR_LINE" | cut -d ':' -f 4)
                    ERROR_SUBTEXT=$(echo "$ERROR_LINE" | cut -d ':' -f 5)
                    echo "$CRATE_NAME,\"$TEST_NAME\",\"$ERROR_TYPE\",\"$ERROR_TEXT\",\"$ERROR_SUBTEXT\"" >> $OUTPUT_CSV
                fi
            done
        else
            continue
        fi
    done
}
echo "crate_name,test_name,error_type,error_text,error_subtext" >> $RESULT_DIR/errors_stack.csv
echo "crate_name,test_name,error_type,error_text,error_subtext" >> $RESULT_DIR/errors_tree.csv
echo "crate_name,test_name,engaged" >> $RESULT_DIR/engaged_stack.csv
echo "crate_name,test_name,engaged" >> $RESULT_DIR/engaged_tree.csv
unpack_errors "stack" "$RESULT_DIR/errors_stack.csv" "$RESULT_DIR/engaged_stack.csv"
unpack_errors "tree" "$RESULT_DIR/errors_tree.csv" "$RESULT_DIR/engaged_tree.csv"
echo "Finished!"