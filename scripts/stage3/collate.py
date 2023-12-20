import os
import sys
import json
import re

RE_MAYBEUNINIT = re.compile(r"error: .*\n.  --> .*\n(    \|\n)*([0-9]+[ ]+\|.* (((std::){0,1}mem::){0,1}(MaybeUninit::uninit\(\).assume_init\(\)))")
RE_MEM_UNINIT = re.compile(r"error: .*\n.  --> .*\n(    \|\n)*([0-9]+[ ]+\|.* (((std::){0,1}mem::){0,1}(uninitialized\(\)))")

def failed():
    print(f"Usage: python3 collate.py [data dir]")
    exit(1)

if(len(sys.argv) != 2):
    failed()

root_dir = sys.argv[1]
if not os.path.exists(root_dir):
    failed()            
data_dir = os.path.join(root_dir, "crates")

# ensure that the directory stage3/crates exists in walk_dir
if not os.path.exists(data_dir):
    failed()

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


def is_maybeuninit():
    pass
def is_mem_uninit(text):
    # find if there's a match against RE_MAYBEUNINIT
    # if so, return the line number and the index where the innermost capturing group starts
    # otherwise, return None
    match = RE_MEM_UNINIT.search(text)
    if match is None:
        return None
    else:
        return (match.group(2), match.start(3))
    


stack_errors_path = os.path.join(root_dir, "stack_error_roots.csv")
if os.path.exists(stack_errors_path):
    os.remove(stack_errors_path)
stack_errors_file = open(stack_errors_path, "a")
stack_errors_file.write("crate_name,test_name,error_root\n")
stack_errors_file.flush()

stack_meta_path = os.path.join(root_dir, "stack_metadata.csv")
if os.path.exists(stack_meta_path):
    os.remove(stack_meta_path)
stack_meta_file = open(stack_meta_path, "a")

tree_errors_path = os.path.join(root_dir, "tree_error_roots.csv")
if os.path.exists(tree_errors_path):
    os.remove(tree_errors_path)
tree_errors_file = open(tree_errors_path, "a")
tree_errors_file.write("crate_name,test_name,error_root\n")
tree_errors_file.flush()

tree_meta_path = os.path.join(root_dir, "tree_metadata.csv")
if os.path.exists(tree_meta_path):
    os.remove(tree_meta_path)
tree_meta_file = open(tree_meta_path, "a")

first_visited_stack = True
first_visited_tree = True
for crate in os.listdir(data_dir):
    stack_dir = os.path.join(data_dir, crate, "stack")
    if os.path.exists(stack_dir):
        (reps,status) = extract_representatives(crate, stack_dir)
        for test in reps:
            stack_errors_file.write(f"{crate},{test},\"{reps[test]}\"\n")
            stack_errors_file.flush()
        if first_visited_stack and flag_headers is not None:
            stack_meta_file.write(flag_headers + "\n")
            first_visited_stack = False
        stack_meta_file.write(status)
        stack_meta_file.flush()
    else:
        print(f"No 'stack' directory found for {crate}")

    tree_dir = os.path.join(data_dir, crate, "tree")

    if not os.path.exists(tree_dir):
        first_visited = (flag_headers is None)
        (reps, status) = extract_representatives(crate, tree_dir)
        for test in reps:
            tree_errors_file.write(f"{crate},{test},\"{reps[test]}\"\n")
            tree_errors_file.flush()
        if first_visited_tree and flag_headers is not None:
            tree_meta_file.write(flag_headers + "\n")
            first_visited_tree = False
        tree_meta_file.write(status)
        tree_meta_file.flush()
    else:
        print(f"No 'tree' directory found for {crate}")

tree_errors_file.close()
stack_errors_file.close()
tree_meta_file.close()
stack_meta_file.close()