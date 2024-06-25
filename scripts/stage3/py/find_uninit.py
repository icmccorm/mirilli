import pandas as pd

# Read CSV files
all_df = pd.read_csv(
    "./results/population.csv",
    names=[
        "crate_name",
        "version",
        "last_updated",
        "downloads",
        "percentile_downloads",
        "avg_daily_downloads",
        "percentile_daily_download",
    ],
    dtype=str,
)
errors_stack = pd.read_csv("./results/stage3/errors_stack.csv")
roots_stack = pd.read_csv("./results/stage3/stack_error_roots.csv")
errors_tree = pd.read_csv("./results/stage3/errors_tree.csv")
roots_tree = pd.read_csv("./results/stage3/tree_error_roots.csv")

# Filter and join for stack errors
rerun_stack = errors_stack[
    errors_stack["error_text"]
    == "using uninitialized data, but this operation requires initialized memory"
]
rerun_stack = rerun_stack.merge(
    roots_stack, on=["crate_name", "test_name"], how="inner"
)
rerun_stack = rerun_stack.merge(all_df, on=["crate_name"], how="inner")
rerun_stack = rerun_stack[["test_name", "crate_name", "version"]]

# Filter and join for tree errors
rerun_tree = errors_tree[
    errors_tree["error_text"]
    == "using uninitialized data, but this operation requires initialized memory"
]
rerun_tree = rerun_tree.merge(roots_tree, on=["crate_name", "test_name"], how="inner")
rerun_tree = rerun_tree.merge(all_df, on=["crate_name"], how="inner")
rerun_tree = rerun_tree[["test_name", "crate_name", "version"]]

# Combine results and write to CSV
rerun_uninit_all = pd.concat([rerun_stack, rerun_tree]).drop_duplicates()
rerun_uninit_all.to_csv("./build/stage3/uninit.csv", index=False, header=False)
