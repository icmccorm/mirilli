# Dataset - A Study of Undefined Behavior Across Foreign Function Boundaries in Rust Libraries
This directory contains the raw dataset produced for each of the steps described in Sections 3.1, 3.3, and 4 of the paper. The raw files are published on [Zenodo](https://zenodo.org/records/12727040). Here, we describe the contents and format of each file provided in the dataset and the compiled output of executing `make build`. We define the columns of each CSV file when they first appear whenever the name is not self-explanatory.

## Setup 
Our Docker image is prepackaged with all necessary dependencies. If you are working outside of the image, you will need version 4.3.1 of [R](https://www.r-project.org/), [renv](https://rstudio.github.io/renv/index.html), and [Python >3.9](https://www.python.org/downloads/). 
You will also need to execute the following command to initialize the R environment (skip if using Docker).
```
R -e "renv::restore()" 
```
Execute the following command to download the dataset and decompress it. 
```
curl -O https://zenodo.org/records/12727040/files/dataset.zip && unzip dataset.zip
```
Files will be placed into the folder `dataset` in the root directory. The dataset is >400MB, so this may take a little while. Once the dataset is downloaded and decompressed, you can compile it with the following command:
```
make build
```

## Root Directory - (`dataset/`)

`├── population.sql`

* This script creates a view `population` within the crates.io database which contains the name and version of all crates that have least one valid (non-yanked) version.

`├── population.csv` 

* The contents of the `population` view from the crates.io dataset on September 20th, 2023.
  
  * Columns: 

    * `crate_name` - The name of the crate
    * `version` -  The crate's version
    * `last_updated` - The date this version was published
    * `downloads` - The number of downloads this crate has received (all versions)
    * `percentile_downloads` - The percentile downloads relative to all crates.
    * `avg_daily_downloads` - The average number of downloads each day (all versions) in the 6 months prior to 9/20/2023
    * `percentile_daily_downloads` - The percentile average daily downloads (all versions) in the 6 months prior to 9/20/2023

`├── exclude.csv`

* This file contains all crates that were excluded from analysis due to causing fatal OOM errors during compilation. 

  * Columns: `crate_name`

`├── bugs.csv` 

* This file lists all unique bugs that we found in our analysis. It is used to generate Table A.4 of our Appendix. We updated this file manually every time we found a new bug. 

  * Columns: `crate_name`,`version`
  
    * `bug_id` - A unique identifier for each bug.
    * `root_crate_name`, `root_crate_version` - The name and version of the crate where the bug was detected, if it was present in a dependency.
    * `fix_loc` - The location of the fix; either "LLVM," "Rust," or "Binding"
    * `annotated_error_type` - A custom error type that we apply, defined in the Appendix.
    * `test_name` - The name of the test that triggered the error in `root_crate` (if defined) or `crate`. 
    * `notes` - Any additional notes about the test
    * `issue` - Links to GitHub issues
    * `pull_request` - Links to GitHub pull requests
    * `commit` - Links to GitHub commits
    * `bug_type_override` - Override the bug type provided by Miri with the value, if defined.
    * `memory_mode` - The memory mode in which the error was found (either "uninit" or "zeroed", blank for both)
    * `error_loc_override` - Override the error location reported by Miri with the provided value (either "LLVM", "Rust", or "Binding")
    * `error_type_override` - Override the error type (more general than bug type) reported by Miri with the value, if defined.

## Stage 1 - Finding Candidate Crates - (`dataset/stage1`)

The directory `stage1` contains results from running the following script:
```
./scripts/stage1/run.sh [population.csv]
```
This script finds the set of crates in our population that had test cases and produced bytecode files during compilation. It creates the following output within `dataset/stage1`:

`├── bytecode`

* A directory containing a `.csv` file for each crate listing the path of every `.bc` file produced when it was compiled.
  
`├── has_bytecode.csv`

* Lists the crates that produced bytecode files.

  * Columns: `crate_name`, `version`

`├── tests`

* This directory contains a `.txt` file for each crate listing the tests that were available. 

`├── failed_download.csv`

* The name and version of each crate that failed to download during the data collection run.

  * Columns: `crate_name`, `version`, `exit_code`
    
`├── status_comp.csv`

* The exit code from natively compiling each crate.

  * Columns: `crate_name`, `version`, `exit_code`

`├── status_lint.csv`

* The exit code from running two custom linting passes, which we describe below.

  * Columns: `crate_name`, `version`, `exit_code`

`├── visited.csv`

* The name and version of each crate that we downloaded and attempted to collect data from in this stage.

  * Columns: `crate_name`, `version`

### Stage 1 - Early Lint

`├── early`

This directory contains the results from the lint defined in `src/early`, which collects the foreign ABIs used in each crate. Running this lint on a crate produces the following JSON file, which lists the location of each construct corresponding to a particular ABI. The `unknown_abis` array is a fallback for ABIs which were not recognized by the lint.
```
{
  "foreign_function_abis": {
    "C": [
      "lib.rs:53:15: 53:51",
    ]
  },
  "static_item_abis": {...},
  "rust_function_abis": {...},
  "unknown_abis": []
}
```
We did not use this data in our final evaluation, but it is included here. 

### Stage 1 - Late Lint

`├── late`

We also created a lint that combines the Rust compiler's [`improper_ctypes`](https://doc.rust-lang.org/stable/nightly-rustc/rustc_lint/types/static.IMPROPER_CTYPES.html) and [`improper_ctypes_definitions`](https://doc.rust-lang.org/stable/nightly-rustc/rustc_lint/types/static.IMPROPER_CTYPES_DEFINITIONS.html) lints and allows us to record instances of improper type use within foreign bindings. We had to create a custom lint, as opposed to recording output from `rustc`, so that we could still detect errors when compilation directives such as `#![allow(improper_ctypes)]` were used. Running these lints produces a CSV file with the following format, which indicates where improper types were used and whether they were ignored due to a compilation directive.
```
{
  "error_id_count": 0,
  "error_id_map": {
    "0": {
      "discriminant": 3,
      "str_rep": "u128",
      "abi": "C",
      "reason": 6
    }
  },
  "foreign_functions": {
    "total_items": 0,
    "item_error_counts": [
      {
        "counts": {
          "0": 1
        },
        "locations": {
          "0": [
            "../bindings.rs"
          ]
        },
        "index": 409,
        "ignored": true
      },
    ],
    "abis": {...}
  },
  "static_items": {...},
  "field_defs": {...},
  "alias_tys": {...},
  "rust_functions": {...},
  "decl_lint_disabled_for_crate": false,
  "defn_lint_disabled_for_crate": false
}
```
The field `error_id_map` associates an ID (0-indexed) to each error detected by either lint. The `error_id_count` indicates the number of unique error IDs. An error is a record containing a `discriminant` ID for the improper type, its string representation (`str_rep`), the ABI of the item where the error occurred, and an ID for the `reason` it occurred. The fields `decl_lint_disabled_for_crate` and `defn_lint_disabled_for_crate` indicate whether either lint was globally disabled for that crate. 

The remaining records list the errors that occurred for each category of foreign item and declaration. Within each of these records, the field `total_items` lists the number of items within the crate. The array `item_error_counts` lists the errors that occur for each item. In the example above, index 409 indicates the (409 + 1)nth item. The field `ignored` indicates whether the errors associated with this item were ignored due to a compilation directive. The record `counts` indicates the number of errors associated with each error ID. The record `locations` maps each error ID to an array of locations within the item where that error occurred. 

`├── reasons.csv`

* Maps integer IDs representing the reason for each improper type error to the string name of each reason.

  * Columns: 
    
    * `reason_name` - The name of the reason within the Rust compiler source.
    * `reason` - The numerical ID of the reason.

`├── discriminants.csv`

* Maps integer IDs for the discriminants of each improper type to the string name of each discriminant.

  * Columns:
    
    * `discriminant` - The numerical discriminant of the type
    * `type_name` - The name of the type within the Rust compiler source.

Similar to the early lints, we ended up not using the data from late lints in our final evaluation, but we include it here in case it is useful.

### Stage 1 - Build Output - (`build/stage1`)

Executing the command `make build/stage1` will produce the directory `build/stage1`, which will contain the following files:

`├── stage2.csv`

* The name and version of each crate that had test cases and produced bytecode. It is the input to Stage 2.

  * Columns (unlabeled): `crate_name`, `version`

`├── stage1.stats.csv`

* This file contains statistics for Stage 1, which are collated and inserted into the text of our paper.

  * Columns: `key`, `value`

`├── lint_info.csv`

* The name of each crate and boolean flags indicating if improper type lints were ignored (yes = true, no = false) at any level, locally or globally.

  * Columns: `crate_name`
    
    * `defn_disabled` - Whether the improper types lint was disabled for *definitions*
    * `decl_disabled` - Whether the improper types lint was disabled for *declarations*

`├── early_abis.csv`

* Lists the location of each ABI used in foreign function, static items, and alias types within each crate visited during the early lint pass. 

  * Columns: `crate_name`
    
    * `category` - The item with the ABI which is either a Rust function ("rust_functions") a foreign static item ("static_items"), or a foreign function defn. or decl. ("foreign_functions")
    * `abi` - The foreign ABI, as documented in the [Rust Reference](https://doc.rust-lang.org/stable/reference/items/external-blocks.html?#abi).
    * `file` - The file where the item occurred.
    * `start_line`, `start_col`, `end_line`, `end_col` - The position within the file where the item occurred.

`├── late_abis.csv`

* Lists the location of each ABI used in foreign function, static items, and alias types within each crate visited during the late lint pass. 

  * Columns: `crate_name`, `abi`, `file`, `start_line`, `start_col`, `end_line`, `end_col`

    * `category` - The same values as `early_abis.csv`, as well as if the item occurred in an alias type ("alias_tys") 

`├── finished_early.csv`

* The names of crates that finished the early lint pass without errors.

  * Columns: `crate_name`

`├── finished_late.csv`

* The names of crates that finished the late lint pass without errors.

  * Columns: `crate_name`

`├── error_info.csv`

* The reasons, ABIs, discriminants, and type names for every improper type error found in each crate.

  * Columns: `crate_name`, `abi`, `discriminant`, `reason`, 
    
    * `err_id` - A unique ID for the error
    * `err_text` - The pretty-printed type for which the error occurred.

`├── error_locations.csv`

* The location and category of each improper type error.

  * Columns: `crate_name`, `err_id`, `category`, `file`, `start_line`, `start_col`, `end_line`, `end_col`

    * `ignored` - Whether the error would have been ignored by the Rust compiler due to improper type lints being disabled.

`├── has_tests.csv`

* The number of test cases for each crate. 

  * Columns: `crate_name`, `test_count`
  
## Stage 2 - Finding Candidate Tests -  (`dataset/stage2`)

The directory `stage2` contains results from running the following script:

```
./scripts/stage2/run.sh [build/stage1/stage2.csv]
```
From each crate with tests and bytecode, it finds the list of test cases that fail in Miri due to an unsupported foreign function call. 

`├── logs`

* This directory contains a subdirectory for each crate visited in Stage 2. The directory of each crate contains a `.txt` file containing the standard output and error from running each test case in Miri.

`├── failed_download.csv`

* The name and version of each crate that failed to download in Stage 2 (empty; no crates failed at this stage)

  * Columns: `crate_name`, `version`, `exit_code`

`├── status_rustc_comp.csv`

* The result of natively compiling the tests for each crate.

  * Columns: `exit_code`, `crate_name`, `test_name`

`├── status_miri_comp.csv`

* The exit code from compiling the tests for each crate within Miri using the command `cargo miri test --tests -q -- --list`

  * Columns: `exit_code`, `crate_name`, `test_name`

`├── tests.csv`

* The exit code from running each test cases in Miri, and an integer flag indicating whether the test terminated due to an unsupported foreign function call. 

  * Columns: `exit_code`, `test_name`, `crate_name`

    * `had_ffi` - The value `0` indicates that a foreign function *was* found. The value `1` indicates that the test failed for some other reason. The value `-1` indicates that the test passed, or that it was manually ignored for use in Miri.

`├── visited.csv`

* The name and version of each crate that we attempted to collect data from in Stage 2.

    * Columns: `crate_name`, `version`

### Stage 2 - Build Output - (`build/stage2`)

Executing the command `make build/stage2` will produce the directory `build/stage2`, which will contain the following files:

`├── stage2-ignored.csv`

* The name of every test (and its crate and version) that was listed as an option when natively compiling its test suite but that did *not* appear when compiling for Miri. 

  * Columns: `test_name`, `crate_name`, `version`

`├── stage2.stats.csv`

* This file contains statistics for Stage 1, which are collated and inserted into the text of our paper.

    * Columns: `key`, `value`

`├── stage3.csv`

* The list of each test (and its crate and version) that failed in Miri due to an unsupported foreign function call. This file is used as the input to Stage 3.

  * Columns (unlabeled): `test_name`, `crate_name`, `version`

## Stage 3 - Evaluation in MiriLLI - (`dataset/stage3`)
The directory `stage3` contains results from running the following script:
```
./scripts/stage3/run.sh [build/stage2/stage3.csv] [-z]
```
This script executes each test case from Stage 2 using MiriLLI. By default, we use the "uninit" memory mode, which allows uninitialized reads to occur in LLVM. The flag `-z` enables the "zeroed" memory mode, which treats uninitialized reads in LLVM as errors, but zero-initializes all LLVM memory by default. 

We ran this script twice on the results from Stage 2; once in its default "uninit" configuration, and once with `-z`.  The root directory contains the file `flags.csv`, which lists the complete set of flags which can be logged by each test execution to track certain behaviors. Results for each run are contained within the `zeroed` and `uninit` directories, respectively. Each directory contains the following set of files. Certain filenames include `[stack | tree]`, which indicate that there are two separate files; one for results when running under the Stacked Borrows model, and one for the Tree Borrows model. 

`├── crates/[crate_name]/llvm_bc.csv`

* The list of individual `.bc` files produced from compiling this crate.

`├── crates/[tree | stack]/[test].err.log`

* Standard error from running the test case `[test]` in MiriLLI under either Stacked or Tree Borrows.

`├── crates/[tree | stack]/[test].out.log`

* Standard output from running the test case `[test]` in MiriLLI under either Stacked or Tree Borrows.

`├── crates/[tree | stack]/[test].flags.csv`

* Flags logged during the test execution which indicate that certain behaviors occurred. A list of all flags and their descriptions can be found in `dataset/stage3/flags.csv` 

`├── failed_download.csv`

* The name and version of each crate that failed to download during Stage 3.

  * Columns: `crate_name`, `version`, `exit_code`

`├── status_miri_comp.csv`

* The exit code from running each test case with Miri.

  * Columns: `exit_code`, `crate_name`, `test_name`

`├── status_native.csv`

* The exit code from running each test case natively.

  * Columns: `exit_code`, `crate_name`, `test_name`

`├── status_native_comp.csv`

* The exit code from natively compiling each test case.

  * Columns: `exit_code`, `crate_name`, `test_name`

`├── visited.csv`

* The crates that we attempted to collect data from in Stage 3.

  * Columns: `crate_name`, `version`

### Stage 3 - Build Output - (`/build/stage3`) 

#### Per-Mode Output (`/build/stage3/[zeroed | uninit]`)

`├── error_info_[tree | stack].csv`

* The outcomes of every test case.

  * Columns: `crate_name`, `test_name`,
  
    * `error_type`, `error_text` - Miri's error messages are formatted "error_type: error_text". For instance, "Undefined Behavior: dereferencing pointer failed:" would have "Undefined Behavior" as the `error_type` and "dereferencing..." as the `error_text`.
    * `error_location_rust` - The location of an error, if it occurred in Rust. Left as "NA" otherwise.
    * `exit_signal_no` - The signal number if the process was terminated by the system. Left as "NA" if the process terminated normally. 
    * `assertion_failure` - Whether the test failed due to an assertion failure written as part of the test case (true = assertion failure, false = other outcome)

`├── error_roots_[tree | stack].csv`

* The source locations of every error.

  * Columns: `crate_name`, `test_name`, 

    * `error_root` - The full stack trace of errors that occurred in LLVM. Left as "NA" if the error occurred in Rust. 

`├── metadata_[tree | stack].csv`

* The flags that were logged for each test case. 

  * Columns: `crate_name`, `test_name`

    * Remaining columns hold integer values (1/0) indicating the presence or absence of each flag listed in `stage3/flags.csv`

`├── tree_summary.csv`

* The types of errors that we observed under Tree Borrows. 

  * Columns: `crate_name`, `test_name`, 
  
    * `action` - Either "read", "write", "retag", or "dealloc"
    * `kind` - Either "Expired", "Insufficient", or "Framing", as defined in the Background section of the paper. 

`├── stack_summary.csv`

* The types of errors that we observed under Stacked Borrows. 

  * Columns: `crate_name`, `test_name`, 
  
    * `action` - Either "read", "write", "retag", or "dealloc"
    * `kind` - "Insufficient" and "Framing" are defined in the Background of section of the paper. "Expired-[action]" indicates an Expired permission error, as defined in Background, caused by the given action. "Out of bounds" indicates that an access occurred using a tag that was not present in the stack for a given location. Tree borrows relaxes this rule, making it unnecessary to have a separate category for access out of bounds errors. 

#### Summarized Output (`/build/stage3`)

`├── errors.csv`

* All test outcomes under each memory mode and aliasing model.

  * Columns: `crate_name`, `version`, `test_name`, `native_comp_exit_code`, `native_exit_code`, `miri_comp_exit_code`, `exit_code_[stack | tree]`, `error_type_[stack | tree]`, `error_text_[stack | tree]`, `error_root_[stack | tree]`, `action_[stack | tree]`, `kind_[stack | tree]`, `assertion_failure_[stack | tree]`, `exit_signal_no_[stack | tree]`

    * `is_foreign_error_[stack | tree]` - Whether the test had an error occur in foreign code under the given memory model (occurred in foreign code = TRUE). 
    * `memory_mode` - Either "zeroed" or "uninit"

`├── errors_unique.csv`

  * Deduplicated errors that occurred under both memory modes.

    * Columns: Every column from `errors.csv`, except for `memory_mode`.

      * `valid_error_[stack | tree]` -  This column was used to help filter results when manually reviewing outcomes. This columns is TRUE if the test failed, exhibited undefined behavior, leaked memory, read uninitialized memory in a dependency, or displayed any other undesired outcome. It is FALSE if the test timed-out, passed, encountered an unsupported operation, or read uninitialized memory in its source. Uninitialized reads in source are not considered "valid" since we encountered an overwhelming number of crates that improperly used `MaybeUninit<T>::assume_init()` or `mem::uninitialized()` (which is instantly undefined behavior in any scenario) and had long since been abandoned. We excluded these abandoned crates from our results and hid these test outcomes after we had found all valid, reportable instances of uninitialized reads in the immediate source of crates. 

      * `num_duplicates` - The number of distinct test outcomes that were deduplicated into this row. 

`├── diff_errors_uninit.csv`

  * Deduplicated test outcomes under the "uninit" memory mode.

    * Columns: Every column from `errors_unique.csv`. 

`├── diff_errors_zeroed.csv`

  * Deduplicated test outcomes under the "uninit" memory mode.

    * Columns: Every column from `errors_unique.csv`. 

`├── failures.csv`

  * Columns: `crate_name`, `test_name`,
  
    * `zeroed` - The aliasing model ("stack" or "tree") under which the test failed when running in the `zeroed` memory mode
    * `uninit` - The aliasing model ("stack" or "tree") under which the test failed when running in the `uninit` memory mode

`├── metadata.csv`

  * The number of unique tests that activated each flag in `./dataset/stage3/flags.csv` under at least one combination of memory mode and aliasing model.

    * Columns: `flag_name`, `n`

`├── stage3.stats.csv`

  * This file contains statistics for Stage 1, which are collated and inserted into the text of our paper.

    * Columns: `key`, `value`