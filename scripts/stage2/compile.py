import os
import sys

def failed():
    print("Usage: python3 parse.py [data dir] [out dir]")
    exit(1)

if len(sys.argv) != 3:
    failed()

data_dir = sys.argv[1]
if not os.path.exists(data_dir):
    failed()

output_dir = sys.argv[2]
if not os.path.exists(output_dir):
    os.makedirs(output_dir, exist_ok=True)

# create and open a file "tests.csv" in the output directory
tests_file = open(os.path.join(output_dir, "tests.csv"), "w")

for root, dirs, files in os.walk(data_dir):
    for file in files:
        if file.endswith(".csv"):
            with open(os.path.join(root, file), "r") as f:
                for line in f:
                    if line.strip() == "":
                        break
                    tests_file.write(line)
tests_file.close()