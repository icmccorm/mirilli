import os
import sys
import json
import re
import parse_tb
import parse_shared
import parse_sb

def read_flags(FLAGS_CSV_PATH):
    with open(FLAGS_CSV_PATH, "r") as f:
        flags = list(map(lambda x: x.strip(), f.readlines()))
        flags.sort()
        return flags

FLAGS_CSV_PATH = "./results/stage3/flags.csv"
FLAGS = read_flags(FLAGS_CSV_PATH)

def check_for_uninit(text):
    return parse_shared.RE_MEM_UNINIT.search(text) is not None
def check_for_maybeuninit(text):
    return parse_shared.RE_MAYBEUNINIT.search(text) is not None
def quote(string):
    return "\"" + string.strip() + "\""
def csv_row(list):
    return ",".join(list).strip() + "\n"

FILES_TO_CLOSE = []

def failed():
    print(f"Usage: python3 collate.py [data dir]")
    exit(1)

if(len(sys.argv) != 2):
    failed()

root_dir = sys.argv[1]
if not os.path.exists(root_dir):
    failed()

base = os.path.basename(root_dir)
data_dir = os.path.join(root_dir, "crates")

if not os.path.exists(data_dir):
    failed()

def open_csv(dir, name, headers):
    global FILES_TO_CLOSE
    path = os.path.join(dir, name)
    if os.path.exists(path):
        os.remove(path)
    file = open(path, "a")
    if len(headers) > 0:
        file.write("%s\n" % ",".join(headers))
        file.flush()
    FILES_TO_CLOSE.append(file)
    return file

def open_csv_for_both(dir, name, headers):
    stack_file_name = "%s_stack.csv" % name
    tree_file_name = "%s_tree.csv" % name
    stack_file = open_csv(dir, stack_file_name, headers)
    tree_file = open_csv(dir, tree_file_name, headers)
    return [stack_file, tree_file]    

def parse_directory(is_tree_borrows, crate_name, directory, roots, metadata, info_file):
    global flag_headers
    files_organized = os.listdir(directory)
    files_organized.sort()
    for filename in files_organized:
        if filename.endswith(".err.log"):
            test_case = os.path.basename(filename)[:-8]
            with open(os.path.join(directory, filename), "r") as f:
                text = f.read()
                (info, borrow_info) = extract_error_info(is_tree_borrows, text)
                if borrow_info is not None:
                    if is_tree_borrows:
                        tree_summary.write(csv_row([crate_name, test_case] + borrow_info))
                        tree_summary.flush()
                    else:
                        stack_summary.write(csv_row([crate_name, test_case] + borrow_info))
                        stack_summary.flush()
                actual_failure = "NA"
                output_path = os.path.join(directory, test_case + ".out.log")
                if os.path.exists(output_path):
                    with open(output_path, "r") as out:
                        actual_failure = extract_failure_status(out.read())
                info_file.write(csv_row([crate_name, test_case] + info + [actual_failure]))
                info_file.flush()

                root = quote(";".join(extract_error_trace(text)))
                roots.write(csv_row([crate_name, test_case, "1", root]))
                roots.flush()
        if filename.endswith(".flags.csv"):
            curr_flags = set(read_flags(os.path.join(directory, filename)))
            test_case = os.path.basename(filename)[:-10]
            flags = []
            for flag in FLAGS:
                if flag in curr_flags:
                    flags.append("1")
                else:
                    flags.append("0")
            metadata.write(csv_row([crate_name, test_case] + flags))
                         
def extract_error_trace(text):
    lines = []
    in_trace = False
    for line in text.split("\n"):
        if line.startswith("---- Foreign Error Trace ----"):
            in_trace = True
            continue
        if line.startswith("----------------------------"):
            in_trace = False
            continue
        if in_trace and not (line.startswith("@")) and not (line.strip() == ""):
            lines.append(line)
    return lines

def extract_failure_status(text):
    actual_failure = "FALSE"
    lines = text.split("\n")
    for line in lines:
        if 'test result: FAILED' in line:
            actual_failure = "TRUE"
    return actual_failure

def extract_error_info(is_tree_borrows, text):
    error_type = "Unknown"
    error_text = "NA"
    error_location = "NA"
    lines = text.split('\n')
    error_type_override = None
    if check_for_maybeuninit(text):
        error_type_override = "Invalid MaybeUninit<T>"
    if check_for_uninit(text):
        error_type_override = "Invalid mem::uninitialized()"
    collect_help_text = False
    help_text = []
    error_found = False
    exit_signal_number = "NA"
    signal_regex = re.compile(r"signal: ([0-9]+)")
    for i, line in enumerate(lines):
        if 'fatal runtime error: stack overflow' in line and not error_found:
            error_type = "Stack Overflow"
            error_text = line
            error_found = True
        elif 'Unhandled type' in line and not error_found:
            error_type = "LLI Internal Error"
            error_text = line
            error_found = True
        elif 'LLVM ERROR:' in line and not error_found:
            error_type = "LLI Internal Error"
            error_text = line
            error_found = True
        elif line.startswith('error: could not compile') and not error_found:
            error_type = "Compilation Failed"
            error_text = line
            error_found = True
        elif line.startswith('error:') and not error_found:
            error_line_number = i
            next_line_number = error_line_number + 1
            next_line = lines[next_line_number] if next_line_number < len(lines) else "NA"
            error_location = next_line.split('-->')[-1].strip() if '-->' in next_line else "NA"
            full_error_text = line[7:]
            error_type = full_error_text.split(':')[0].strip() if ":" in full_error_text else full_error_text
            error_text = full_error_text
            if 'unsupported operation' in error_type:
                error_type = "Unsupported Operation"
            if 'test failed' in error_type:
                error_type = "Test Failed"
            if 'failed to run custom build command for' in error_type:
                error_type = "Build Failed"
            if 'the compiler unexpectedly panicked. this is a bug' in error_type:
                error_type = "ICE"
            if 'the main thread terminated without waiting for all remaining threads' in error_type:
                error_type = "Main Terminated Early"
            if 'memory leaked' in error_type:
                error_type = "Memory Leaked"
            error_found = True
            collect_help_text = True
            help_text.append(error_text)
        elif line.startswith('error:') and error_found:
            collect_help_text = False
        elif "help:" in line and collect_help_text and error_found:
            help_text.append(line.split("help:")[1])
        elif "process didn't exit successfully" in line:
            match = signal_regex.search(line)
            if match:
                exit_signal_number = match.group(1)
    error_subtype = None
    if(error_type == "Borrowing Violation"):
        if not is_tree_borrows:
            error_subtype = parse_sb.stack_error(help_text)
        else:
            error_subtype = parse_tb.tb_error(help_text)
    error_type = error_type_override if error_type_override is not None else error_type
    return ([error_type, quote(error_text), quote(error_location), exit_signal_number], error_subtype)

(stack_roots, tree_roots) = open_csv_for_both(root_dir, "error_roots", ["crate_name", "test_name", "is_foreign", "error_root"])
(stack_meta, tree_meta) = open_csv_for_both(root_dir, "metadata", ["crate_name", "test_name"] + FLAGS)
(stack_info, tree_info) = open_csv_for_both(root_dir, "error_info", ["crate_name", "test_name", "error_type", "error_text", "error_location_rust","exit_signal_no","actual_failure"])
tree_summary = open_csv(root_dir, "tree_summary.csv", ["crate_name", "test_name"] + parse_shared.COLUMNS)
stack_summary = open_csv(root_dir, "stack_summary.csv", ["crate_name", "test_name"] + parse_shared.COLUMNS)

for crate in os.listdir(data_dir):
    stack_dir = os.path.join(data_dir, crate, "stack")
    tree_dir = os.path.join(data_dir, crate, "tree")
    crate_name = os.path.basename(crate)
    if os.path.exists(stack_dir):
        parse_directory(False, crate_name, stack_dir, stack_roots, stack_meta, stack_info)
    else:
        print(f"No 'stack' directory found for {crate}")
    if os.path.exists(tree_dir):
        parse_directory(True, crate_name, tree_dir, tree_roots, tree_meta, tree_info)
    else:
        print(f"No 'tree' directory found for {crate}")
for file in FILES_TO_CLOSE:
    file.flush()
    file.close()