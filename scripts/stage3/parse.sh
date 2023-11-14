ROOT_DIR=$1
rm -f "$ROOT_DIR/errors_stack.csv"
rm -f "$ROOT_DIR/errors_tree.csv"
touch "$ROOT_DIR/errors_stack.csv"
touch "$ROOT_DIR/errors_tree.csv"
function unpack_errors() {
    ERROR_ROOT_DIR=$1
    OUTPUT_CSV=$2
    echo "Parsing errors for '$ERROR_ROOT_DIR'..."
    for CRATE_DIR in "$ROOT_DIR"/crates/*; do
        CRATE_NAME=$(basename "$CRATE_DIR")
        echo "Unpacking '$1' errors for $CRATE_NAME..."
        # if the directory isn't empty
        if [ "$(ls -A "$CRATE_DIR"/"$ERROR_ROOT_DIR")" ]; then
            for LOG in "$CRATE_DIR"/"$ERROR_ROOT_DIR"/*.err.log; do
                TEST_NAME=$(basename "$LOG" .err.log)

                FATAL_RUNTIME_LINE=$(cat "$LOG" | grep -n '^fatal runtime error: stack overflow' | head -n 1)
                if [ "$FATAL_RUNTIME_LINE" != "" ]; then
                    echo "$CRATE_NAME,\"$TEST_NAME\",\"$FATAL_RUNTIME_LINE\",\"Stack Overflow\",\"\",\"\"" >> $OUTPUT_CSV
                    continue
                fi
                UNHANDLED_TYPE_LINE=$(cat "$LOG" | grep -n '^Unhandled type' | head -n 1)
                if [ "$UNHANDLED_TYPE_LINE" != "" ]; then
                    UNHANDLED_TYPE_TEXT=$(echo "$UNHANDLED_TYPE_LINE" | cut -d ':' -f 3)
                    echo "$CRATE_NAME,\"$TEST_NAME\",\"$UNHANDLED_TYPE_LINE\",\"LLI Internal Error\",\"Unhandled type\",\"$UNHANDLED_TYPE_TEXT\"" >> $OUTPUT_CSV
                    continue
                fi
                LLVM_ERROR_LINE=$(cat "$LOG" | grep -n '^LLVM ERROR:' | head -n 1)
                if [ "$LLVM_ERROR_LINE" != "" ]; then
                    LLVM_ERROR_TEXT=$(echo "$LLVM_ERROR_LINE" | cut -d ':' -f 3)
                    echo "$CRATE_NAME,\"$TEST_NAME\",\"$LLVM_ERROR_LINE\",\"LLI Internal Error\",\"$LLVM_ERROR_TEXT\",\"\"" >> $OUTPUT_CSV
                    continue
                fi
                # check if there's a line of the form "error: could not compile [...] due to previous error"
                # if so, we can ignore the rest of the log
                PREVIOUS_ERROR_LINE=$(cat "$LOG" | grep -n '^error: could not compile' | head -n 1)
                if [ "$PREVIOUS_ERROR_LINE" != "" ]; then
                    ERROR_LINE=$(cat "$LOG" | grep -n '^error:' | head -n 1)
                    ERROR_TEXT=$(echo "$ERROR_LINE" | cut -d ':' -f 3)
                    echo "$CRATE_NAME,\"$TEST_NAME\",\"$PREVIOUS_ERROR_LINE\",\"Compilation Failed\",\"$ERROR_TEXT\",\"\"" >> $OUTPUT_CSV
                    continue
                fi
                
                # find the first line that includes error, but doesn't necessarily start with it:
                # this is the first error that occurred during compilation
                ERROR_LINE=$(cat "$LOG" | grep -n '^error:' | head -n 1)
                if [ "$ERROR_LINE" != "" ]; then
                    ERROR_TYPE=$(echo "$ERROR_LINE" | cut -d ':' -f 3)
                    FULL_ERROR_TYPE=${ERROR_LINE#*error:}
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
                    echo "$CRATE_NAME,\"$TEST_NAME\",\"$FULL_ERROR_TYPE\",\"$ERROR_TYPE\",\"$ERROR_TEXT\",\"$ERROR_SUBTEXT\"" >> $OUTPUT_CSV
                fi
            done
        else
            continue
        fi
    done
}
echo "crate_name,test_name,full_error_text,error_type,error_text,error_subtext" >> $ROOT_DIR/errors_stack.csv
echo "crate_name,test_name,full_error_text,error_type,error_text,error_subtext" >> $ROOT_DIR/errors_tree.csv
unpack_errors "stack" "$ROOT_DIR/errors_stack.csv" "$ROOT_DIR/engaged_stack.csv"
unpack_errors "tree" "$ROOT_DIR/errors_tree.csv" "$ROOT_DIR/engaged_tree.csv"
echo "Finished!"