import json
import os
import sys
from tqdm import tqdm

if (len(sys.argv) == 1):
    print(f"Usage: python3 compile.py [raw data] [destination dir]")
    exit(1)
walk_dir = sys.argv[1]

if (len(sys.argv) < 3):
    out_dir = "./build/stage1"
else:
    out_dir = sys.argv[2]

if not os.path.exists(out_dir):
    os.makedirs(out_dir)

FILES_TO_CLOSE = []

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

early_abis = open_csv(out_dir, "early_abis.csv", ["crate_name", "category", "abi", "file", "start_line", "start_col", "end_line", "end_col"])
late_abis = open_csv(out_dir, "late_abis.csv", ["crate_name", "category", "abi", "file", "start_line", "start_col", "end_line", "end_col"])
finished_early = open_csv(out_dir, "finished_early.csv", ["crate_name"])
finished_late = open_csv(out_dir, "finished_late.csv", ["crate_name"])
error_category_counts = open_csv(out_dir, "category_error_counts.csv", ["crate_name", "category", "item_index", "err_id", "count", "ignored"])
err_info = open_csv(out_dir, "error_info.csv", ["crate_name", "abi", "discriminant", "reason", "err_id", "err_text"])
err_locations = open_csv(out_dir, "error_locations.csv", ["crate_name", "err_id", "category", "ignored", "file", "start_line", "start_col", "end_line", "end_col"])
lint_status_info = open_csv(out_dir, "lint_info.csv", ["crate_name", "defn_disabled", "decl_disabled"])
has_tests = open_csv(out_dir, "has_tests.csv", ["crate_name", "test_count"])

CAT_FOREIGN_FN = "foreign_functions"
CAT_STATIC_ITEM = "static_items"
CAT_RUST_FN = "rust_functions"
CAT_ALIAS_TYS = "alias_tys"
CAT_UNKNOWN = "unknown"

def read_json(path, name):
    fd = open(path, "r")
    json_obj = json.loads(fd.read())
    fd.close()
    name = os.path.splitext(name)[0]
    return name, json_obj

def location_to_csv(loc):
    items = list(map(str.strip, loc.split(':')))
    file = items[0]
    start_line = items[1]
    start_col = items[2]
    end_line = items[3]
    end_col = items[4]        
    return f'"{file}",{start_line},{start_col},{end_line},{end_col}'

def process_abis(name, category, json):
    entries = ""
    for key, loc_list in json.items():
        for loc in loc_list:
            entries += f"{name},{category},{key},{location_to_csv(loc)}\n"
    return entries

def process_error_info(name, json):
    info_entries = ""
    error_map = json["error_id_map"]
    for err_id in error_map:
        e_entry = error_map[err_id]
        e_text = e_entry["str_rep"]
        e_abi = e_entry["abi"]
        e_discr = e_entry["discriminant"]
        e_reason = e_entry["reason"]
        info_entries += f'{name},{e_abi},{e_discr},{e_reason},{err_id},"{e_text}"\n'
    return info_entries

def process_error_category(name, category, ignored, json):
    abi_counts = json[category]["abis"]
    abi_entries = process_abis(name, category, abi_counts)

    item_error_counts = json[category]["item_error_counts"]
    category_entries = ""
    loc_entries = ""

    for entry in item_error_counts:
        loc_ignored = ignored
        loc_ignored = entry["ignored"] or ignored
        for err_id in entry["counts"]:
            count = entry["counts"][err_id]
            category_entries += f'{name},{category},{entry["index"]},{err_id},{count},{str(loc_ignored).lower()}\n'
            if err_id not in entry["locations"] or len(entry["locations"][err_id]) == 0:
                print(
                    f"Unable to resolve location for error ID {err_id} of crate {name}")
                exit(1)
        for err_id in entry["locations"]:
            for loc in entry["locations"][err_id]:
                loc_entries += f'{name},{err_id},{category},{str(loc_ignored).lower()},{location_to_csv(loc)}\n'
    return {
        "category": category_entries,
        "locations": loc_entries,
        "abis": abi_entries,
    }

if (os.path.isdir(walk_dir)):
    for dir in os.listdir(walk_dir):
        if dir == "early":
            early = os.path.join(walk_dir, dir)
            print("Processing early lint results...")
            for early_result in tqdm(os.listdir(early)):
                path_to_early_result = os.path.join(early, early_result)
                name, early_result_json = read_json(
                    path_to_early_result, early_result)
                finished_early.write(f"{name}\n")
                early_abis.write(process_abis(name, CAT_FOREIGN_FN,
                                           early_result_json["foreign_function_abis"]))
                early_abis.write(process_abis(name, CAT_RUST_FN,
                                           early_result_json["rust_function_abis"]))
                early_abis.write(process_abis(name, CAT_STATIC_ITEM,
                                           early_result_json["static_item_abis"]))
        if dir == "late":
            late = os.path.join(walk_dir, dir)
            print("Processing late lint results...")
            for late_result in tqdm(os.listdir(late)):
                path_to_late_result = os.path.join(late, late_result)
                name, late_result_json = read_json(
                    path_to_late_result, late_result)
                finished_late.write(f"{name}\n")
                defn_lint_disabled = late_result_json["defn_lint_disabled_for_crate"]
                decl_lint_disabled = late_result_json["decl_lint_disabled_for_crate"]
                lint_status_info.write(f'{name},{str(defn_lint_disabled).lower()},{str(decl_lint_disabled).lower()}\n')
                err_info.write(process_error_info(name, late_result_json))
                for category in [CAT_FOREIGN_FN, CAT_RUST_FN, CAT_STATIC_ITEM, CAT_ALIAS_TYS]:
                    data = process_error_category(
                        name, category, decl_lint_disabled, late_result_json
                    )
                    error_category_counts.write(data["category"])
                    err_locations.write(data["locations"])
                    late_abis.write(data["abis"])

        if dir == "tests":
            tests = os.path.join(walk_dir, dir)
            print("Processing test results...")
            for test_result in tqdm(os.listdir(tests)):
                path_to_test_result = os.path.join(tests, test_result)
                with open(path_to_test_result, "r") as test_result_txt:
                    crate_name = os.path.splitext(os.path.basename(path_to_test_result))[0]
                    test_result_content = test_result_txt.readlines()
                    test_count = len(
                        [line for line in test_result_content if line.endswith(": test\n")])
                    has_tests.write(f"{crate_name},{test_count}\n")
                    
else:
    print("Invalid input directory.")

for file in FILES_TO_CLOSE:
    file.flush()
    file.close()