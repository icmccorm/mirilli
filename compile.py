import json
import os
import sys

walk_dir = sys.argv[1]
out_dir = sys.argv[2]
if(out_dir is None): out_dir = "./data"
abis = "crate_name,abi,category,count\n"
defn_types = ""
decl_types = ""
disabled_decl = ""
disabled_defn = ""
finished_early = "name\n"
finished_late = "name\n"
error_category_counts = "crate_name,category,item_index,err_id,count,ignored\n"
err_info = "crate_name,abi,discriminant,reason,err_id,err_text\n"
err_locations = "crate_name,err_id,category,ignored,file,start_line,start_col,end_line,end_col\n"
late_abi_counts = "crate_name,category,abi,count\n"
lint_status_info = "crate_name,defn_disabled,decl_disabled\n"

CAT_FOREIGN_FN = "foreign_functions"
CAT_STATIC_ITEM = "static_items"
CAT_RUST_FN = "rust_functions"

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

def process_abis(name, json):
    entries = ""
    for key, value in json["foreign_function_abis"].items():
        entries += f"{name},{CAT_FOREIGN_FN},{key},{value}\n"
    for key, value in json["static_item_abis"].items():
        entries += f"{name},{CAT_STATIC_ITEM},{key},{value}\n"
    for key, value in json["rust_function_abis"].items():
        entries += f"{name},{CAT_RUST_FN},{key},{value}\n"
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
    category_entries = ""
    item_error_counts = json[category]["item_error_counts"]
    loc_entries = ""
    for entry in item_error_counts:
        loc_ignored = ignored
        loc_ignored = entry["ignored"] or ignored
        for err_id in entry["counts"]:
            count = entry["counts"][err_id]
            category_entries += f'{name},{category},{entry["index"]},{err_id},{count},{str(loc_ignored).lower()}\n'
            if err_id not in entry["locations"] or len(entry["locations"][err_id]) == 0:
                print(f"Unable to resolve location for error ID {err_id} of crate {name}")
                exit(1) 
        for err_id in entry["locations"]:
            for loc in entry["locations"][err_id]:
                items = list(map(str.strip, loc.split(':')))
                file = items[0]
                start_line = items[1]
                start_col = items[2]
                end_line = items[3]
                end_col = items[4]
                loc_entries += f'{name},{err_id},{category},{str(loc_ignored).lower()},"{file}",{start_line},{start_col},{end_line},{end_col}\n'
    return {
        "category": category_entries,
        "locations": loc_entries,
    }
if(os.path.isdir(walk_dir)):
    for dir in os.listdir(walk_dir):
        if dir == "early":
            early = os.path.join(walk_dir, dir)
            for early_result in os.listdir(early):
                path_to_early_result = os.path.join(early, early_result)
                name, early_result_json = read_json(path_to_early_result, early_result)
                print(f"{name}-early")
                finished_early += f"{name}\n"
                for abi, count in early_result_json["foreign_function_abis"].items():
                    abis += f"{name},{abi},{CAT_FOREIGN_FN},{count}\n"
                for abi, count in early_result_json["rust_function_abis"].items():
                    abis += f"{name},{abi},{CAT_STATIC_ITEM},{count}\n"
                for abi, count in early_result_json["static_item_abis"].items():
                    abis += f"{name},{abi},{CAT_RUST_FN},{count}\n"
        if dir == "late":
            late = os.path.join(walk_dir, dir)
            for late_result in os.listdir(late):
                path_to_late_result = os.path.join(late, late_result)
                name, late_result_json = read_json(
                    path_to_late_result, late_result)
                finished_late += f"{name}\n"
                process_abis(name, late_result_json)
                if late_result_json["error_id_count"] != 0:
                    print(f"{name}-late")
                    defn_lint_disabled = late_result_json["defn_lint_disabled_for_crate"]
                    decl_lint_disabled = late_result_json["decl_lint_disabled_for_crate"]
                    lint_status_info += f'{name},{str(defn_lint_disabled).lower()},{str(decl_lint_disabled).lower()}\n'

                    err_info += process_error_info(name, late_result_json)

                    foreign_data = process_error_category(
                        name, CAT_FOREIGN_FN, decl_lint_disabled, late_result_json
                    )
                    error_category_counts += foreign_data["category"]
                    err_locations += foreign_data["locations"]

                    static_data = process_error_category(
                        name, CAT_STATIC_ITEM, decl_lint_disabled, late_result_json
                    )
                    error_category_counts += static_data["category"]
                    err_locations += static_data["locations"]
                    
                    rust_data = process_error_category(
                        name, CAT_RUST_FN, defn_lint_disabled, late_result_json
                    )
                    error_category_counts += rust_data["category"]
                    err_locations += rust_data["locations"]
                    
    dump(finished_early, os.path.join(out_dir,"finished_early.csv"))
    dump(finished_late, os.path.join(out_dir, "finished_late.csv"))
    dump(late_abi_counts, os.path.join(out_dir,"late_abis.csv"))
    dump(error_category_counts, os.path.join(out_dir, "category_error_counts.csv"))
    dump(abis, os.path.join(out_dir, "abis.csv"))
    dump(disabled_decl, os.path.join(out_dir, "disabled_decl.csv"))
    dump(disabled_defn, os.path.join(out_dir, "disabled_defn.csv"))
    dump(err_locations, os.path.join(out_dir, "error_locations.csv"))
    dump(err_info, os.path.join(out_dir, "error_info.csv"))
    dump(lint_status_info, os.path.join(out_dir, "lint_info.csv"))
else:
    print("Invalid input directory.")