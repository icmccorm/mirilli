import json
import os
import sys

if (len(sys.argv) == 1):
    print(f"Usage: python3 compile.py [raw data] [destination dir]")
    exit(1)
walk_dir = sys.argv[1]

if (len(sys.argv) < 3):
    out_dir = "./build/stage1/lints"
else:
    out_dir = sys.argv[2]

if not os.path.exists(out_dir):
    os.makedirs(out_dir)

early_abis = "crate_name,category,abi,file,start_line,start_col,end_line,end_col\n"
late_abis = "crate_name,category,abi,file,start_line,start_col,end_line,end_col\n"
defn_types = ""
decl_types = ""
finished_early = "crate_name\n"
finished_late = "crate_name\n"
error_category_counts = "crate_name,category,item_index,err_id,count,ignored\n"
err_info = "crate_name,abi,discriminant,reason,err_id,err_text\n"
err_locations = "crate_name,err_id,category,ignored,file,start_line,start_col,end_line,end_col\n"
lint_status_info = "crate_name,defn_disabled,decl_disabled\n"

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

def dump(contents, path):
    fd = open(path, "w")
    fd.writelines(contents)
    fd.close()

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
            for early_result in os.listdir(early):
                path_to_early_result = os.path.join(early, early_result)
                name, early_result_json = read_json(
                    path_to_early_result, early_result)
                finished_early += f"{name}\n"
                early_abis += process_abis(name, CAT_FOREIGN_FN,
                                           early_result_json["foreign_function_abis"])
                early_abis += process_abis(name, CAT_RUST_FN,
                                           early_result_json["rust_function_abis"])
                early_abis += process_abis(name, CAT_STATIC_ITEM,
                                           early_result_json["static_item_abis"])
        if dir == "late":
            late = os.path.join(walk_dir, dir)
            for late_result in os.listdir(late):
                path_to_late_result = os.path.join(late, late_result)
                name, late_result_json = read_json(
                    path_to_late_result, late_result)
                finished_late += f"{name}\n"
                defn_lint_disabled = late_result_json["defn_lint_disabled_for_crate"]
                decl_lint_disabled = late_result_json["decl_lint_disabled_for_crate"]
                lint_status_info += f'{name},{str(defn_lint_disabled).lower()},{str(decl_lint_disabled).lower()}\n'
                err_info += process_error_info(name, late_result_json)
                for category in [CAT_FOREIGN_FN, CAT_RUST_FN, CAT_STATIC_ITEM, CAT_ALIAS_TYS]:
                    data = process_error_category(
                        name, category, decl_lint_disabled, late_result_json
                    )
                    error_category_counts += data["category"]
                    err_locations += data["locations"]
                    late_abis += data["abis"]

    dump(finished_early, os.path.join(out_dir, "finished_early.csv"))
    dump(finished_late, os.path.join(out_dir, "finished_late.csv"))
    dump(late_abis, os.path.join(out_dir, "late_abis.csv"))
    dump(error_category_counts, os.path.join(
        out_dir, "category_error_counts.csv"))
    dump(early_abis, os.path.join(out_dir, "early_abis.csv"))
    dump(err_locations, os.path.join(out_dir, "error_locations.csv"))
    dump(err_info, os.path.join(out_dir, "error_info.csv"))
    dump(lint_status_info, os.path.join(out_dir, "lint_info.csv"))
else:
    print("Invalid input directory.")