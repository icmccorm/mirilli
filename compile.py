import json
import os
import sys

walk_dir = sys.argv[1]

abis = ""
defn_types = ""
decl_types = ""
disabled_decl = ""
disabled_defn = ""

def read_json(path):
    fd = open(path, "r")
    json_obj = json.loads(fd.read())
    fd.close()
    name = os.path.splitext(early_result)[0]
    return name, json_obj

def dump(contents, path):
    fd = open(path, "w")
    fd.writelines(contents)
    fd.close()

for partition in os.listdir(walk_dir):
    f = os.path.join(walk_dir, partition)
    for dir in os.listdir(f):
        if(dir == "early"):
            early = os.path.join(f, dir)
            for early_result in os.listdir(early):
                path_to_early_result = os.path.join(early, early_result)
                name, early_result_json = read_json(path_to_early_result)
                for i in early_result_json["abis"]:
                    abis += f'{name},{i}\n'
                if "decl_lint_blocked" in early_result_json and early_result_json["decl_lint_blocked"]:
                    disabled_decl += f'{name}\n'
                if "decl_lint_blocked" in early_result_json and early_result_json["defn_lint_blocked"]:
                    disabled_defn += f'{name}\n'
        elif (dir == "late"):
            late = os.path.join(f, dir)
            for late_result in os.listdir(late):
                path_to_late_result = os.path.join(late, late_result)
                name, late_result_json = read_json(path_to_late_result)

            
abis_out = dump(abis, "./abis.csv")
disabled_decl_out = dump(disabled_decl, "./disabled_decl.csv")
disabled_defn_out = dump(disabled_defn, "./disabled_defn.csv")
