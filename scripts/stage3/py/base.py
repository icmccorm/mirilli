import os
import pandas as pd
import re
import constants

# Create the directory if it doesn't exist
stage3_root = "./build/stage3/"
if not os.path.exists(stage3_root):
    os.makedirs(stage3_root)

# Define the constants
STACK_OVERFLOW_TXT = "Stack Overflow"
UNSUPP_ERR_TXT = "Unsupported Operation"
LLI_ERR_TXT = "LLI Internal Error"
TIMEOUT_ERR_TXT = "Timeout"
TIMEOUT_PASS_ERR_TXT = "Passed/Timeout"
TEST_FAILED_TXT = "Test Failed"
TERMINATED_EARLY_ERR_TXT = "Main Terminated Early"
USING_UNINIT_FULL_ERR_TXT = (
    "using uninitialized data, but this operation requires initialized memory"
)
INTEROP_ERR_TXT = "LLI Interoperation Error"
UB_MAYBEUNINIT = "Using Uninitialized Memory"
UB_MEM_UNINIT = "Invalid mem::uninitialized()"
PASS_ERR_TEXT = "Passed"
SCALAR_MISMATCH_TEXT = "Scalar Size Mismatch"

UNWIND_ERR_TEXT = "unwinding past the topmost frame of the stack"
UNWIND_ERR_TYPE = "Unwinding Past Topmost Frame"

CROSS_LANGUAGE_ERR_TEXT = "deallocating alloc"
CROSS_LANGUAGE_ERR_TYPE = "Cross-Language Deallocation"

INVALID_VALUE_UNINIT_ERR_TYPE = "Using Uninitialized Memory"
INVALID_VALUE_UNINIT_ERR_TEXT = "encountered uninitialized memory, but expected"

INVALID_VALUE_UNALIGNED_ERR_TYPE = "Unaligned Reference"
INVALID_VALUE_UNALIGNED_ERR_TEXT = "invalid value: encountered an unaligned reference"

INVALID_ENUM_TAG_ERR_TEXT = "but expected a valid enum tag"
INVALID_VALUE_ENUM_TAG_ERR_TYPE = "Invalid Enum Tag"


all_df = pd.read_csv(
    os.path.join("./results/population.csv"),
    names=[
        "crate_name",
        "version",
        "last_updated",
        "downloads",
        "percentile_downloads",
        "avg_daily_downloads",
        "percentile_daily_download",
    ],
)[["crate_name", "version"]]


# Define the function
def can_deduplicate_without_error_root(error_type):
    return error_type in [
        LLI_ERR_TXT,
        UNSUPP_ERR_TXT,
        TIMEOUT_ERR_TXT,
        TIMEOUT_PASS_ERR_TXT,
        TERMINATED_EARLY_ERR_TXT,
    ]


def deduplicate_error_text(df):
    df["error_text"] = df["error_text"].str.replace(r"alloc[0-9]+", "alloc", regex=True)
    df["error_text"] = df["error_text"].str.replace(r"<[0-9]+>", "<>", regex=True)
    df["error_text"] = df["error_text"].str.replace(
        r"call [0-9]+", "call <>", regex=True
    )
    df["error_text"] = df.apply(
        lambda row: re.sub(rf"^{re.escape(row['error_type'])}:", "", row["error_text"]),
        axis=1,
    )
    df["error_text"] = df["error_text"].str.replace(
        r"0x[0-9a-f]+\[noalloc\]", "[noalloc]", regex=True
    )
    df["error_text"] = df["error_text"].str.strip()
    return df


def correct_error_type(df):
    error_mappings = [
        (UNWIND_ERR_TEXT, UNWIND_ERR_TYPE),
        ("deallocating alloc", CROSS_LANGUAGE_ERR_TYPE),
        (CROSS_LANGUAGE_ERR_TEXT, CROSS_LANGUAGE_ERR_TYPE),
        (INVALID_VALUE_UNALIGNED_ERR_TEXT, INVALID_VALUE_UNALIGNED_ERR_TYPE),
        (INVALID_ENUM_TAG_ERR_TEXT, INVALID_VALUE_ENUM_TAG_ERR_TYPE),
        (INVALID_VALUE_UNINIT_ERR_TEXT, INVALID_VALUE_UNINIT_ERR_TYPE),
        ("deadlock", "Deadlock"),
        ("is not supported for use in shims.", UNSUPP_ERR_TXT),
    ]

    for pattern, error_type in error_mappings:
        df["error_type"] = df.apply(
            lambda row: error_type
            if re.search(pattern, row["error_text"])
            else row["error_type"],
            axis=1,
        )

    return df


# Check if the error type is valid
def valid_error_type(error_type, trace):
    invalid_types = {
        UNSUPP_ERR_TXT,
        LLI_ERR_TXT,
        SCALAR_MISMATCH_TEXT,
        TIMEOUT_ERR_TXT,
        TIMEOUT_PASS_ERR_TXT,
        UB_MAYBEUNINIT,
        UB_MEM_UNINIT,
    }
    return error_type not in invalid_types or (
        error_type in {UB_MAYBEUNINIT, UB_MEM_UNINIT}
        and trace.startswith("/root/.cargo/registry/src/index.crates.io")
    )


# Check if the exit code indicates a passed test
def passed(exit_code):
    return exit_code == 0


# Check if the exit code indicates a timeout
def timed_out(exit_code):
    return exit_code == 124


# Check if the exit code indicates an error
def errored_exit_code(exit_code):
    return not passed(exit_code) and not timed_out(exit_code)


# Filter rows where the test failed in either mode
def failed_in_either_mode(df):
    return df[
        (df["error_type_stack"] == TEST_FAILED_TXT) & df["exit_signal_no_stack"].isna()
        | (df["error_type_tree"] == TEST_FAILED_TXT) & df["exit_signal_no_stack"].isna()
    ]


# Filter rows where there was a stack overflow in either mode
def overflowed_in_either_mode(df):
    return df[
        (df["error_type_stack"] == STACK_OVERFLOW_TXT)
        | (df["error_type_tree"] == STACK_OVERFLOW_TXT)
    ]


# Check if the error is in a dependency
def error_in_dependency(error_root):
    return bool(re.search(r"/root/.cargo/registry/src/index.crates.io-", error_root))


# Check if the error type is a possible non-failure bug
def possible_non_failure_bug(error_type, trace):
    return valid_error_type(error_type, trace) and error_type not in {
        TEST_FAILED_TXT,
        STACK_OVERFLOW_TXT,
    }


# Keep only rows with possible non-failure bugs
def keep_only_ub(df):
    return df[
        (
            df.apply(
                lambda row: possible_non_failure_bug(
                    row["error_type_stack"], row["error_root_stack"]
                ),
                axis=1,
            )
        )
        | (
            df.apply(
                lambda row: possible_non_failure_bug(
                    row["error_type_tree"], row["error_root_tree"]
                ),
                axis=1,
            )
        )
    ]


def prepare_errors(directory, error_type):
    error_path = os.path.join(directory, f"error_info_{error_type}.csv")
    root_path = os.path.join(directory, f"error_roots_{error_type}.csv")

    # Read CSV files
    errors = pd.read_csv(error_path)
    errors = errors.merge(
        all_df, on="crate_name"
    )  # Assuming 'all' is a dataframe named 'all_df'
    error_roots = pd.read_csv(root_path)

    # Select specific columns
    error_rust_locations = errors[["crate_name", "test_name", "error_location_rust"]]

    # Join and mutate
    error_roots = error_roots.merge(
        error_rust_locations, on=["crate_name", "test_name"], how="outer"
    )
    error_roots["is_foreign_error"] = ~error_roots["error_root"].isna()
    error_roots["error_root"] = error_roots.apply(
        lambda row: row["error_location_rust"]
        if pd.isna(row["error_root"])
        else row["error_root"],
        axis=1,
    )
    error_roots = error_roots.drop(columns=["error_location_rust"])

    # Join, correct error type and deduplicate error text
    errors = errors.merge(error_roots, on=["crate_name", "test_name"], how="outer")
    errors = correct_error_type(errors)
    errors = deduplicate_error_text(errors)

    # Read exit codes
    exit_codes_path = os.path.join(directory, f"status_{error_type}.csv")
    exit_codes = pd.read_csv(
        exit_codes_path, names=["exit_code", "crate_name", "test_name"]
    )

    # Join exit codes and mutate error type
    errors = errors.merge(exit_codes, on=["crate_name", "test_name"], how="outer")
    errors["error_type"] = errors.apply(
        lambda row: TIMEOUT_ERR_TXT
        if timed_out(row["exit_code"])
        else row["error_type"],
        axis=1,
    )
    errors["borrow_mode"] = error_type

    # Read borrow summary
    borrow_summary_path = os.path.join(directory, f"{error_type}_summary.csv")
    borrow_summary = pd.read_csv(borrow_summary_path)

    # Join borrow summary
    errors = errors.merge(borrow_summary, on=["crate_name", "test_name"], how="outer")

    return errors


def compile_errors(dir):
    basename = os.path.basename(dir)

    stack_errors = prepare_errors(dir, "stack")
    tree_errors = prepare_errors(dir, "tree")

    status_col_names = ["exit_code", "crate_name", "test_name"]

    native_comp_status = (
        pd.read_csv(os.path.join(dir, "status_native_comp.csv"), names=status_col_names)
        .rename(columns={"exit_code": "native_comp_exit_code"})
        .drop_duplicates()
    )
    native_status = (
        pd.read_csv(os.path.join(dir, "status_native.csv"), names=status_col_names)
        .rename(columns={"exit_code": "native_exit_code"})
        .drop_duplicates()
    )
    miri_comp_status = (
        pd.read_csv(os.path.join(dir, "status_miri_comp.csv"), names=status_col_names)
        .rename(columns={"exit_code": "miri_comp_exit_code"})
        .drop_duplicates()
    )

    status = native_comp_status.merge(
        native_status, on=["crate_name", "test_name"], how="outer"
    ).merge(miri_comp_status, on=["crate_name", "test_name"], how="outer")
    errors = pd.concat([stack_errors, tree_errors])

    errors = (
        errors[
            [
                "crate_name",
                "test_name",
                "borrow_mode",
                "error_type",
                "error_text",
                "is_foreign_error",
                "error_root",
                "exit_code",
                "assertion_failure",
                "exit_signal_no",
                "action",
                "kind",
            ]
        ]
        .drop_duplicates()
        .pivot_table(
            index=["crate_name", "test_name"],
            columns="borrow_mode",
            values=[
                "error_type",
                "error_text",
                "is_foreign_error",
                "error_root",
                "exit_code",
                "assertion_failure",
                "exit_signal_no",
                "action",
                "kind",
            ],
            aggfunc=lambda x: " ".join(x),
        )
    )

    all_df = pd.read_csv(
        os.path.join("./results/population.csv"),
        names=[
            "crate_name",
            "version",
            "last_updated",
            "downloads",
            "percentile_downloads",
            "avg_daily_downloads",
            "percentile_daily_download",
        ],
    ).loc[:, ["crate_name", "version"]]

    result = status.merge(errors, on=["crate_name", "test_name"], how="outer").merge(
        all_df, on=["crate_name"], how="inner"
    )
    result["memory_mode"] = basename
    return result[
        [
            "crate_name",
            "version",
            "test_name",
            "native_comp_exit_code",
            "native_exit_code",
            "miri_comp_exit_code",
            "exit_code_stack",
            "exit_code_tree",
            "error_type_stack",
            "error_type_tree",
            "error_text_stack",
            "error_text_tree",
            "is_foreign_error_stack",
            "is_foreign_error_tree",
            "error_root_stack",
            "error_root_tree",
            "action_stack",
            "action_tree",
            "kind_stack",
            "kind_tree",
            "assertion_failure_stack",
            "assertion_failure_tree",
            "exit_signal_no_stack",
            "exit_signal_no_tree",
            "memory_mode",
        ]
    ]


def merge_passes_and_timeouts(df):
    df["exit_code_stack"] = df.apply(
        lambda x: 0
        if timed_out(x["exit_code_stack"]) and x["error_type_stack"] == TIMEOUT_ERR_TXT
        else x["exit_code_stack"],
        axis=1,
    )
    df["exit_code_tree"] = df.apply(
        lambda x: 0
        if timed_out(x["exit_code_tree"]) and x["error_type_tree"] == TIMEOUT_ERR_TXT
        else x["exit_code_tree"],
        axis=1,
    )
    df["error_type_stack"] = df.apply(
        lambda x: TIMEOUT_PASS_ERR_TXT
        if passed(x["exit_code_stack"])
        else x["error_type_stack"],
        axis=1,
    )
    df["error_type_tree"] = df.apply(
        lambda x: TIMEOUT_PASS_ERR_TXT
        if passed(x["exit_code_tree"])
        else x["error_type_tree"],
        axis=1,
    )
    return df


def deduplicate(df):
    # Filtering for deduplication
    can_deduplicate = df[
        (
            (
                df["error_type_stack"].isna()
                | (df["error_type_stack"] != TEST_FAILED_TXT)
            )
            & (
                df["error_type_tree"].isna()
                | (df["error_type_tree"] != TEST_FAILED_TXT)
            )
            & df.apply(lambda x: _can_deduplicate_row(x), axis=1)
        )
    ]

    # Deduplicate
    deduplicated = (
        can_deduplicate.groupby(
            [col for col in can_deduplicate.columns if col != "test_name"]
        )
        .first()
        .reset_index()
    )

    # Count duplicates
    deduplicated["num_duplicates"] = deduplicated.groupby(
        [col for col in deduplicated.columns if col != "test_name"]
    )["test_name"].transform("size")

    # Error in dependencies
    error_in_deps = deduplicated[
        (
            (
                deduplicated.apply(
                    lambda x: error_in_dependency(x["error_root_stack"]), axis=1
                )
                & deduplicated.apply(
                    lambda x: error_in_dependency(x["error_root_tree"]), axis=1
                )
            )
            | (
                deduplicated["error_root_stack"].isna()
                & deduplicated.apply(
                    lambda x: error_in_dependency(x["error_root_tree"]), axis=1
                )
            )
            | (
                deduplicated["error_root_tree"].isna()
                & deduplicated.apply(
                    lambda x: error_in_dependency(x["error_root_stack"]), axis=1
                )
            )
        )
    ]

    # Remove error in dependencies
    deduplicated = deduplicated[~deduplicated.isin(error_in_deps)].dropna()
    error_in_deps["num_duplicates"] = error_in_deps.groupby(
        [
            col
            for col in error_in_deps.columns
            if col not in ["test_name", "crate_name", "version"]
        ]
    )["test_name"].transform("size")

    # Not deduplicable
    not_deduplicable = df[~df.isin(can_deduplicate)].dropna()
    not_deduplicable["num_duplicates"] = 1

    return pd.concat([not_deduplicable, deduplicated, error_in_deps])


def _can_deduplicate_row(row):
    return (
        not errored_exit_code(row["exit_code_stack"])
        or not pd.isna(row["error_root_stack"])
        or can_deduplicate_without_error_root(row["error_type_stack"])
    ) and (
        not errored_exit_code(row["exit_code_tree"])
        or not pd.isna(row["error_root_tree"])
        or can_deduplicate_without_error_root(row["error_type_tree"])
    )


def keep_only_valid_errors(df):
    return (
        df[
            (passed(df["native_comp_exit_code"]) & passed(df["miri_comp_exit_code"]))
            & (
                errored_exit_code(df["exit_code_stack"])
                | errored_exit_code(df["exit_code_tree"])
            )
        ]
        .assign(
            valid_error_stack=df.apply(
                lambda x: valid_error_type(
                    x["error_type_stack"], x["error_root_stack"]
                ),
                axis=1,
            ),
            valid_error_tree=df.apply(
                lambda x: valid_error_type(x["error_type_tree"], x["error_root_tree"]),
                axis=1,
            ),
        )
        .query("valid_error_tree | valid_error_stack")
    )


def compile_metadata(dir):
    stack_meta = pd.read_csv(os.path.join(dir, "metadata_stack.csv")).assign(
        borrow_mode="stack"
    )
    tree_meta = pd.read_csv(os.path.join(dir, "metadata_tree.csv")).assign(
        borrow_mode="tree"
    )
    basename = os.path.basename(dir)
    return (
        pd.concat([stack_meta, tree_meta])
        .assign(memory_mode=basename)
        .loc[
            :,
            ["crate_name", "test_name", "borrow_mode", "memory_mode"]
            + [
                col
                for col in stack_meta.columns
                if col not in ["crate_name", "test_name", "borrow_mode", "memory_mode"]
            ],
        ]
    )


def summarize_metadata(df):
    counts_under_configuration = len(df[["test_name", "crate_name"]].drop_duplicates())
    by_config = df.melt(
        id_vars=["crate_name", "test_name", "borrow_mode", "memory_mode"],
        var_name="name",
    ).drop(columns=["crate_name", "test_name"])
    summary = (
        by_config.groupby(["borrow_mode", "memory_mode", "name"])
        .size()
        .reset_index(name="count")
    )
    summary["percent"] = (summary["count"] / counts_under_configuration).round(1)
    return summary


def deduplicate_label_write(df, path):
    df = df.drop_duplicates().loc[
        :,
        [
            "mode",
            "crate_name",
            "version",
            "test_name",
            "error_type_stack",
            "error_type_tree",
            "exit_code_stack",
            "exit_code_tree",
            "assertion_failure_stack",
            "assertion_failure_tree",
            "exit_signal_no_stack",
            "exit_signal_no_tree",
        ],
    ]
    df["errored_in"] = df.apply(
        lambda x: "Both"
        if errored_exit_code(x["exit_code_tree"])
        and errored_exit_code(x["exit_code_stack"])
        else (
            "Tree"
            if errored_exit_code(x["exit_code_tree"])
            else ("Stack" if errored_exit_code(x["exit_code_stack"]) else pd.NA)
        ),
        axis=1,
    )
    df["assertion_failure"] = df.apply(
        lambda x: x["assertion_failure_tree"]
        if x["errored_in"] == "Tree"
        else x["assertion_failure_stack"],
        axis=1,
    )
    df["exit_signal_no"] = df.apply(
        lambda x: x["exit_signal_no_tree"]
        if x["errored_in"] == "Tree"
        else x["exit_signal_no_stack"],
        axis=1,
    )
    df.loc[
        :,
        [
            "mode",
            "crate_name",
            "version",
            "test_name",
            "errored_in",
            "error_type_stack",
            "error_type_tree",
            "assertion_failure",
            "exit_signal_no",
        ],
    ].to_csv(path, index=False)
