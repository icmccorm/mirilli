import os
import sys


def failed():
    print(f"Usage: python3 collate.py [data dir]")
    exit(1)

if(len(sys.argv) != 2):
    failed()

root_dir = os.path.join(sys.argv[1], "stage3")
if not os.path.exists(root_dir):
    failed()

data_dir = os.path.join(root_dir, "crates")

# ensure that the directory stage3/crates exists in walk_dir
if not os.path.exists(data_dir):
    failed()

def extract_lines(text):
    lines = []
    in_trace = False
    for line in text.split("\n"):
        if line.startswith("---- Foreign Error Trace ----"):
            in_trace = True
            continue
        if line.startswith("----------------------------"):
            in_trace = False
            continue
        if in_trace:
            lines.append(line)
    return lines

def extract_representatives(directory):
    representatives = {}
    files_organized = os.listdir(directory)
    # alphabetize
    files_organized.sort()
    for filename in files_organized:
        if filename.endswith(".err.log"):
            with open(os.path.join(directory, filename), "r") as f:
                text = f.read()
                test_case = os.path.basename(filename)[:-8]
                lines = extract_lines(text)
                if len(lines) > 0:
                    representatives[test_case] = lines[0]
    return representatives

stack_errors_path = os.path.join(root_dir, "stack_error_roots.csv")
if os.path.exists(stack_errors_path):
    os.remove(stack_errors_path)
stack_errors_file = open(stack_errors_path, "a")
stack_errors_file.write("crate_name,test_name,error_root\n")
stack_errors_file.flush()

tree_errors_path = os.path.join(root_dir, "tree_error_roots.csv")
if os.path.exists(tree_errors_path):
    os.remove(tree_errors_path)
tree_errors_file = open(tree_errors_path, "a")
tree_errors_file.write("crate_name,test_name,error_root\n")
tree_errors_file.flush()

for crate in os.listdir(data_dir):
    stack_dir = os.path.join(data_dir, crate, "stack")
    if not os.path.exists(stack_dir):
        print(f"No 'stack' directory found for {crate}")
        continue
    reps = extract_representatives(stack_dir)
    for test in reps:
        stack_errors_file.write(f"{crate},{test},\"{reps[test]}\"\n")
        stack_errors_file.flush()

    tree_dir = os.path.join(data_dir, crate, "tree")
    if not os.path.exists(tree_dir):
        print(f"No 'tree' directory found for {crate}")
        continue    
    reps = extract_representatives(tree_dir)
    for test in reps:
        tree_errors_file.write(f"{crate},{test},\"{reps[test]}\"\n")
        tree_errors_file.flush()

tree_errors_file.close()
stack_errors_file.close()