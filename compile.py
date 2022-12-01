import json
import os
import sys

walk_dir = sys.argv[1]
out_dir = sys.argv[2]
if(out_dir is None): out_dir = "./data"

foreign_module_abis = "name,abi,count\n"
rust_function_abis = "name,abi,count\n"

defn_types = ""
decl_types = ""
disabled_decl = ""
disabled_defn = ""

finished_early = "name\n"
finished_late = "name\n"
base_column_names = "crate_name,category,"
error_category_counts = base_column_names + "item_index,abi,id,count,err_id\n"
error_string_counts = base_column_names + "text,id,count\n"
error_relative_counts = base_column_names + "item_index,num_errors\n"
error_locations = base_column_names + "crate_name,err_id,location"
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

def process_error_locations(json, name):
    entries = ""
    location_map = json["error_locations"]
    for k in location_map:
        for loc in location_map[k]:
            entries += f'{name},{k},"{loc}"\n'
    return entries

def process_error_category(category, json, name):
    category_entries = ""
    count_entries = ""
    str_rep_entries = ""
    item_error_counts = json[category]["item_error_counts"]
    error_str = {}
    for entry in item_error_counts:
        error_count = 0
        for error_type in entry:
            error_entry = json["error_id_map"][error_type]
            discriminant = int(error_entry["discriminant"])
            str_rep = error_entry["str_rep"]
            if (str_rep, discriminant) not in error_entry:
                error_str[(str_rep, discriminant)] = 1
            else:
                error_str[(str_rep, discriminant)] += 1
            error_count += entry[error_type]
            category_entries += f'{name},{category},{0},{error_entry["abi"]},{discriminant},{entry[error_type]},{error_type}\n'
        count_entries += f"{name},{category},{0},{error_count}\n"
    for key in error_str.keys():
        str_rep_entries += f'{name},{category},"{key[0]}",{key[1]},{error_str[key]}\n'
    return {
        "by_category": category_entries,
        "by_count": count_entries,
        "by_str_rep": str_rep_entries,
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
                for abi, count in early_result_json["foreign_module_abis"].items():
                    foreign_module_abis += f"{name},{abi},{count+1}\n"
                for abi, count in early_result_json["rust_function_abis"].items():
                    rust_function_abis += f"{name},{abi},{count+1}\n"
                if (
                    "foreign_module_lint_blocked" in early_result_json
                    and early_result_json["foreign_module_lint_blocked"]
                ):
                    disabled_decl += f"{name}\n"
                if (
                    "rust_function_lint_blocked" in early_result_json
                    and early_result_json["rust_function_lint_blocked"]
                ):
                    disabled_defn += f"{name}\n"
        if dir == "late":
            late = os.path.join(walk_dir, dir)
            for late_result in os.listdir(late):
                path_to_late_result = os.path.join(late, late_result)
                name, late_result_json = read_json(
                    path_to_late_result, late_result)
                finished_late += f"{name}\n"
                if late_result_json["error_id_count"] != 0:
                    print(f"{name}-late")
                    error_locations += process_error_locations(late_result_json, name)
                    foreign_data = process_error_category(
                        "foreign_functions", late_result_json, name
                    )
                    error_category_counts += foreign_data["by_category"]
                    error_relative_counts += foreign_data["by_count"]
                    error_string_counts += foreign_data["by_str_rep"]

                    static_data = process_error_category(
                        "static_items", late_result_json, name
                    )
                    error_category_counts += static_data["by_category"]
                    error_relative_counts += static_data["by_count"]
                    error_string_counts += static_data["by_str_rep"]

                    rust_data = process_error_category(
                        "rust_functions", late_result_json, name
                    )
                    error_category_counts += rust_data["by_category"]
                    error_relative_counts += rust_data["by_count"]
                    error_string_counts += rust_data["by_str_rep"]
    dump(finished_early, os.path.join(out_dir,"finished_early.csv"))
    dump(finished_late, os.path.join(out_dir, "finished_late.csv"))
    dump(error_string_counts, os.path.join(out_dir, "string_error_counts.csv"))
    dump(error_relative_counts, os.path.join(out_dir, "item_error_counts.csv"))
    dump(error_category_counts, os.path.join(out_dir, "category_error_counts.csv"))
    dump(foreign_module_abis, os.path.join(out_dir, "foreign_module_abis.csv"))
    dump(rust_function_abis, os.path.join(out_dir, "rust_function_abis.csv"))
    dump(disabled_decl, os.path.join(out_dir, "disabled_decl.csv"))
    dump(disabled_defn, os.path.join(out_dir, "disabled_defn.csv"))
    dump(error_locations, os.path.join(out_dir, "error_locations.csv"))
else:
    print("Invalid input directory.")