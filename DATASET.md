# Dataset - A Study of Undefined Behavior Across Foreign Function Boundaries in Rust Libraries
This directory contains the raw dataset produced for each of the steps described in Sections 3.1, 3.3, and 4 of the paper. The raw files are published on [Zenodo](https://zenodo.org/records/12727040). The dataset is currently restricted pending receipt of reports for a few remaining bugs; the embargo will be lifted on August 19th, 2024. Here, we describe the contents and format of each file provided in the dataset and the compiled output of executing `make build`. We define the columns of each CSV file when they first appear whenever the name is not self-explanatory.

## Setup 
Our Docker image is prepackaged with all necessary dependencies. If you are working outside of the image, you will need version 4.3.1 of [R](https://www.r-project.org/), [renv](https://rstudio.github.io/renv/index.html), and [Python >3.9](https://www.python.org/downloads/). 
You will also need to execute the following command to initialize the R environment (skip if using Docker).
```
R -e "renv::restore()" 
```
Visit the Zenodo page and find the download link for the file `data.raw.tar.gz`. Execute the following command to download the dataset and decompress it. 
```
curl -O [link to data.raw.tar.gz] && tar -xvzf data.raw.tar.gz
```
Files will be placed into the folder `dataset` in the root directory. The dataset is >400MB, so this may take a little while. Once the dataset is downloaded and decompressed, you can compile it with the following command:
```
make
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



# Compiled Dataset
In each stage, we export a file `stage[n].stats.csv` which contains several statistics that are useful for our paper or for debugging purposes. These statistics are formatted as key value pairs. When the dataset is compiled, these files are concatenated into the following files:
```
build
...
├── stats.csv
└── stats_long.csv
```
The file `stats.csv` has a column for each key, while `stats_long.csv` has the columns `key` and `value`. 
The following table enumerates and describes each key. These descriptions are also provided within our dataset in the file `stat_key_descriptions.csv`.


| Key                                                | Data Collection Stage | Description                                                                                                                                                                    |
|----------------------------------------------------|:---------------------:|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| num_crates_unfiltered                              |           1           | Number of crates, both valid and invalid (yanked).                                                                                                                             |
| num_crates_all                                     |           1           | Number of crates with a valid, published  version.                                                                                                                             |
| num_crates_compiled                                |           1           | Number of crates that compiled successfully.                                                                                                                                   |
| num_crates_had_tests                               |           1           | Number of crates that had test cases.                                                                                                                                          |
| num_crates_had_bytecode                            |           1           | Number of crates that produced LLVM bitcode during their build process.                                                                                                        |
| num_crates_had_tests_and_bytecode                  |           1           | Number of crates that had test cases and produced LLVM bitcode during their build process.                                                                                     |
| test_count_overall                                 |           1           | Total number of test cases for crates that produced LLVM bitcode.                                                                                                              |
| tests_failed_ffi                                   |           2           | Tests that failed due to a foreign function call.                                                                                                                              |
| tests_failed                                       |           2           | Tests that failed for any reason, including foreign function calls.                                                                                                            |
| tests_passed                                       |           2           | Tests that passed                                                                                                                                                              |
| tests_timed_out                                    |           2           | Tests that timed out (>10 minutes)                                                                                                                                             |
| tests_disabled                                     |           2           | Tests that were disabled manually via #[ignore] or CFG directives.                                                                                                             |
| meta_crates_aggregateasbytes                       |           3           | Crates that passed aggregate values as integers.                                                                                                                               |
| meta_crates_expansion                              |           3           | Crates where we used scalar pair expansion. (Aggregates passed through multiple parameters)                                                                                    |
| meta_crates_exposedpointerfromrustatboundary       |           3           | Crates where pointers were passed as integers to LLVM via implicit casts.                                                                                                      |
| meta_crates_fromaddrcastrust                       |           3           | Crates where integers were implicitly cast into pointers when returned from LLVM to Rust.                                                                                      |
| meta_crates_llvmengaged                            |           3           | Crates where LLI was able to interpret a foreign function call.                                                                                                                |
| meta_crates_llvminttoptr                           |           3           | Crates where the inttoptr instruction was executed in foreign code.                                                                                                            |
| meta_crates_llvminvokedconstructor                 |           3           | Crates where a constructor was invoked for the LLVM module                                                                                                                     |
| meta_crates_llvminvokeddestructor                  |           3           | Crates where a destructor was invoked for the LLVM module.                                                                                                                     |
| meta_crates_llvmmultithreading                     |           3           | Crates where multiple threads executed foreign functions simultaneously.                                                                                                       |
| meta_crates_llvmonresolve                          |           3           | Crates where a pointer was passed without provenance from LLVM to Rust, requiring us to resolve its Allocation ID manually and assign a wildcard tag.                          |
| meta_crates_llvmptrtoint                           |           3           | Crates where the ptrtoint instruction was executed in foreign code.                                                                                                            |
| meta_crates_llvmreaduninit                         |           3           | Crates where LLVM read uninitialized memory.                                                                                                                                   |
| meta_crates_scalarpairinsinglearg                  |           3           | Crates where a scalar pair value was passed as a single argument to LLVM.                                                                                                      |
| meta_crates_sizebasedtypeinference                 |           3           | Crates where we needed to use the size of an underlying allocation to determine the type to assign to pointers passed as arguments to Miri's shims.                            |
| meta_aggregateasbytes                              |           3           | Tests that passed aggregate values as integers.                                                                                                                                |
| meta_expansion                                     |           3           | Tests that passed aggregate values as integers.                                                                                                                                |
| meta_exposedpointerfromrustatboundary              |           3           | Tests where we used scalar pair expansion. (Aggregates passed through multiple parameters)                                                                                     |
| meta_fromaddrcastrust                              |           3           | Tests where pointers were passed as integers to LLVM via implicit casts.                                                                                                       |
| meta_llvmengaged                                   |           3           | Tests where integers were implicitly cast into pointers when returned from LLVM to Rust.                                                                                       |
| meta_llvminttoptr                                  |           3           | Tests where LLI was able to interpret a foreign function call.                                                                                                                 |
| meta_llvminvokedconstructor                        |           3           | Tests where the inttoptr instruction was executed in foreign code.                                                                                                             |
| meta_llvminvokeddestructor                         |           3           | Tests where a constructor was invoked for the LLVM module                                                                                                                      |
| meta_llvmmultithreading                            |           3           | Tests where a destructor was invoked for the LLVM module.                                                                                                                      |
| meta_llvmonresolve                                 |           3           | Tests where multiple threads executed foreign functions simultaneously.                                                                                                        |
| meta_llvmptrtoint                                  |           3           | Tests where a pointer was passed without provenance from LLVM to Rust, requiring us to resolve its Allocation ID manually and assign a wildcard tag.                           |
| meta_llvmreaduninit                                |           3           | Tests where the ptrtoint instruction was executed in foreign code.                                                                                                             |
| meta_scalarpairinsinglearg                         |           3           | Tests where LLVM read uninitialized memory.                                                                                                                                    |
| meta_sizebasedtypeinference                        |           3           | Tests where a scalar pair value was passed as a single argument to LLVM.                                                                                                       |
| num_tests_engaged                                  |           3           | Tests where we needed to use the size of an underlying allocation to determine the type to assign to pointers passed as arguments to Miri's shims.                             |
| num_crates_engaged                                 |           3           | Crates where LLI was able to interpret a foreign function call.                                                                                                                |
| num_tests_not_engaged_both                         |           3           | Tests where LLI did not call a foreign function under both memory modes.                                                                                                       |
| num_tests_not_engaged_one                          |           3           | Tests that only executed a foreign function in one of the two memory modes (zeroed or uninit).                                                                                 |
| num_failures_raw                                   |           3           | Number of tests with an erroneous failure.                                                                                                                                     |
| num_failures                                       |           3           | Number of deduplicated failures.                                                                                                                                               |
| num_errors_shared_raw                              |           3           | Number of tests that encountered the same error in both memory modes.                                                                                                          |
| num_errors_shared                                  |           3           | Number of deduplicated errors that occurred in both memory modes.                                                                                                              |
| num_errors_zeroed_raw                              |           3           | Number of tests with errors that only occurred in the zeroed memory mode.                                                                                                      |
| num_errors_zeroed                                  |           3           | Number of unique errors in the zeroed memory mode.                                                                                                                             |
| num_errors_uninit_raw                              |           3           | Number of tests with errors that only occurred in the uninit memory mode.                                                                                                      |
| num_errors_uninit                                  |           3           | Number of unique errors in the uninit memory mode.                                                                                                                             |
| location_binding                                   |           3           | Number of unique, confirmed bugs that occurred at a foreign function binding.                                                                                                  |
| location_llvm                                      |           3           | Number of unique, confirmed bugs that occurred in LLVM.                                                                                                                        |
| location_rust                                      |           3           | Number of unique, confirmed bugs that occurred in Rust.                                                                                                                        |
| error_category_ownership                           |           3           | Number of ownership bugs.                                                                                                                                                      |
| error_category_typing                              |           3           | Number of typing bugs                                                                                                                                                          |
| error_category_allocation                          |           3           | Number of allocation bugs                                                                                                                                                      |
| error_category_crates_allocation                   |           3           | Number of crates with an allocation bug                                                                                                                                        |
| error_category_crates_ownership                    |           3           | Number of crates with an ownership bug                                                                                                                                         |
| error_category_crates_typing                       |           3           | Number of crates with a typing bug                                                                                                                                             |
| daily_greater_than_10k                             |           3           | Number of crates with more than 10,000 daily downloads during our observation period.                                                                                          |
| daily_less_than_100                                |           3           | Number of crates with less than 100 daily downloads during our observation period.                                                                                             |
| daily_less_than_10                                 |           3           | Number of crates with less than 10 daily downloads during our observation period.                                                                                              |
| bugs_fixed                                         |           3           | Number of bugs fixed since our evaluation.                                                                                                                                     |
| annotated_cross-language_free                      |           3           | Number of cross-language deallocation bugs.                                                                                                                                    |
| annotated_erroneous_failure                        |           3           | Number of erroneous failures.                                                                                                                                                  |
| annotated_freeing_through_mut_ref                  |           3           | Number of bugs caused by freeing through a mutable reference                                                                                                                   |
| annotated_incomplete_initialization                |           3           | Number of incomplete initialization bugs                                                                                                                                       |
| annotated_incorrect_integer_width                  |           3           | Number of bugs due to incorrect integer widths in foreign function bindings.                                                                                                   |
| annotated_incorrect_const                          |           3           | Number of errors due to foreign function bindings with pointer-type parameters that were incorrectly labelled as const in C.                                                   |
| annotated_logical_error                            |           3           | Number of bugs caused by logical errors in the application.                                                                                                                    |
| annotated_missing_c_destructor                     |           3           | Number of leaks caused by missing calls to a C destructor.                                                                                                                     |
| annotated_missing_return_type                      |           3           | Number of incorrect FFI bindings with missing return types.                                                                                                                    |
| annotated_missing_from_raw                         |           3           | Number of memory leaks caused by neglecting to call from_raw in Rust.                                                                                                          |
| annotated_out_of_bounds_access                     |           3           | Number of accesses out-of-bounds.                                                                                                                                              |
| annotated_phantom_unsafecell                       |           3           | Number of bugs caused by the semantics of UnsafeCell within PhantomData.                                                                                                       |
| annotated_sharing_mut_ref                          |           3           | Number of bugs caused by duplicating a mutable reference.                                                                                                                      |
| annotated_uninitialized_padding                    |           3           | Number of bugs caused by uninitialized padding bytes within a struct.                                                                                                          |
| annotated_const_ref_as_mut_ptr                     |           3           | Number of bugs where a reference of type &T was incorrectly cast into a mutable pointer.                                                                                       |
| error_count_cross-language_free                    |           3           | Number of bugs labelled by Miri as cross-language deallocation.                                                                                                                |
| error_count_incorrect_binding                      |           3           | Number of bugs labelled by Miri as an incorrect foreign function.                                                                                                              |
| error_count_invalid_enum_tag                       |           3           | Number of bugs labelled as having an invalid enum tag by Miri.                                                                                                                 |
| error_count_memory_leaked                          |           3           | Number of bugs labelled as a memory leak by Miri                                                                                                                               |
| error_count_out_of_bounds_access                   |           3           | Number of bugs labelled as an access-out-of-bounds by Miri                                                                                                                     |
| error_count_tree_borrows                           |           3           | Number of bugs labelled as a Tree Borrows violation by Miri.                                                                                                                   |
| error_count_uninitialized_memory                   |           3           | Number of bugs labelled as an uninitialized access by Miri.                                                                                                                    |
| crate_count_cross-language_free                    |           3           | Number of rates with a cross-language deallocation bug, as labelled by Miri.                                                                                                   |
| crate_count_incorrect_binding                      |           3           | Number of bugs labelled as cross-language deallocation by Miri                                                                                                                 |
| crate_count_invalid_enum_tag                       |           3           | Number of bugs labelled as cross-language deallocation by Miri                                                                                                                 |
| crate_count_memory_leaked                          |           3           | Number of bugs labelled as cross-language deallocation by Miri                                                                                                                 |
| crate_count_out_of_bounds_access                   |           3           | Number of bugs labelled as cross-language deallocation by Miri                                                                                                                 |
| crate_count_tree_borrows                           |           3           | Number of bugs labelled as cross-language deallocation by Miri                                                                                                                 |
| crate_count_uninitialized_memory                   |           3           | Number of bugs labelled as cross-language deallocation by Miri                                                                                                                 |
| num_bugs                                           |           3           | Total number of bugs.                                                                                                                                                          |
| num_crates_with_bugs                               |           3           | Total number of test cases with bugs.                                                                                                                                          |
| stack_crates_total                                 |           3           | Number of crates with stacked borrows violations.                                                                                                                              |
| stack_tests_total                                  |           3           | Number of tests with stacked borrows violations.                                                                                                                               |
| stack_no_tb_crates_total                           |           3           | Number of crates with stacked borrows violations that were no longer UB under Tree Borrows.                                                                                    |
| stack_no_tb_tests_total                            |           3           | Number of test cases with Stacked Borrows violations that were no longer UB under Tree Borrows.                                                                                |
| stack_error_no_tb_crates_expired-uniqueretag       |           3           | Number of crates with tests that triggered an expired permission error under Stacked Borrows due to a unique retag that did not have an aliasing violation under Tree Borrows. |
| stack_error_no_tb_crates_expired-write             |           3           | Number of crates with tests that triggered an expired permission error under Stacked Borrows due to a write access that did not have an aliasing violation under Tree Borrows. |
| stack_error_no_tb_crates_protected                   |           3           | Number of crates with tests that triggered a protected permission error under Stacked Borrows that is no longer undefined behavior under Tree Borrows.                         |
| stack_error_no_tb_crates_insufficient              |           3           | Number of crates that triggered an unsufficient permission error under Stacked Borrows that was not undefined behavior under Tree Borrows.                                     |
| stack_error_no_tb_crates_out_of_bounds             |           3           | Number of crates that triggered an access out of bounds error under Stacked Borrows that was not undefined behavior under Tree Borrows.                                        |
| stack_error_total                                  |           3           | Number of tests that had a Stacked Borrows violation.                                                                                                                          |
| stack_error_expired-uniqueretag                    |           3           | Number of tests that triggered an expired permission error under Stacked Borrows due to a unique retag.                                                                        |
| stack_error_expired-write                          |           3           | Number of tests that triggered an expired permission error under Stacked Borrows due to a write access.                                                                        |
| stack_error_protected                                |           3           | Number of tests that triggered a protected permission error under Stacked Borrows.                                                                                             |
| stack_error_insufficient                           |           3           | Number of tests that triggered an unsufficient permission error under Stacked Borrows.                                                                                         |
| stack_error_out_of_bounds                          |           3           | Number of tests that triggered an access out of bounds error under Stacked Borrows.                                                                                            |
| stack_error_crates_expired-uniqueretag             |           3           | Number of tests that triggered an expired permission error under Stacked Borrows due to a unique retag.                                                                        |
| stack_error_crates_expired-write                   |           3           | Number of crates that triggered an expired permission error under Stacked Borrows due to a write access.                                                                       |
| stack_error_crates_protected                         |           3           | Number of crates with tests that triggered a protected permission error under Stacked Borrows.                                                                                 |
| stack_error_crates_insufficient                    |           3           | Number of crates with tests that triggered an unsufficient permission error under Stacked Borrows that was not undefined behavior under Tree Borrows.                          |
| stack_error_crates_out_of_bounds                   |           3           | Number of crates with tests that triggered an access out of bounds error under Stacked Borrows that was not undefined behavior under Tree Borrows.                             |
| stack_error_no_tb_expired-uniqueretag              |           3           | Number of tests that triggered an expired permission error under Stacked Borrows due to a write access that did not have an aliasing violation under Tree Borrows.             |
| stack_error_no_tb_protected                          |           3           | Number of tests that triggered a protected permission error under Stacked Borrows that is no longer undefined behavior under Tree Borrows.                                     |
| stack_error_no_tb_insufficient                     |           3           | Number of tests that triggered an unsufficient permission error under Stacked Borrows that was not undefined behavior under Tree Borrows.                                      |
| stack_error_no_tb_out_of_bounds                    |           3           | Number of tests that triggered an access out of bounds error under Stacked Borrows that was not undefined behavior under Tree Borrows.                                         |
| stack_error_no_tb_total                            |           3           | Number of test cases with a Stacked Borrows violation that did not have a Tree Borrows violation.                                                                              |
| error_avg_percentage_unsupp_dyn_asm                |           3           | Average percentage of tests across each memory mode that failed due to unsupported inline assembly instructions.                                                               |
| error_avg_percentage_unsupp_inst                   |           3           | Average percentage of tests across each memory mode that failed due to unsupported LLVM instructions.                                                                          |
| error_avg_percentage_unsupp_llvm_type_shim         |           3           | Average percentage of tests across each memory mode that failed due to unsupported types passed from LLVM to Miri's shim functions.                                            |
| error_avg_percentage_unsupp_other                  |           3           | Average percentage of tests across each memory mode that failed due to other uncategorized operations.                                                                         |
| error_avg_percentage_unsupp_x86_fp80               |           3           | Average percentage of tests across each memory mode that failed due to lack of support for 80-bit floating point types.                                                        |
| error_avg_percentage_error                         |           3           | Average percentage of errors across each memory mode that triggered an error.                                                                                                  |
| error_avg_percentage_passed                        |           3           | Average percentage of errors across each memory mode that passed.                                                                                                              |
| error_avg_percentage_test_failed                   |           3           | Average percentage of errors across each memory mode that failed.                                                                                                              |
| error_avg_percentage_timeout                       |           3           | Average percentage of tests across each memory mode that timed out.                                                                                                            |
| error_avg_percentage_unsupported_operation         |           3           | Average percentage of tests across each memory mode that triggered an unsupported operation.                                                                                   |
| error_avg_percentage_unsupported_operation_in_lli  |           3           | Average percentage of tests across each memory mode that triggered an unsupported operation in LLI.                                                                            |
| error_avg_percentage_unsupported_operation_in_miri |           3           | Average percentage of tests across each memory mode that triggered an unsupported operation in Miri.                                                                           |
| error_avg_percentage_unwinding_past_topmost_frame  |           3           | Average percentage of tests across each memory mode that errored due to unwinding across foreign function boundaries.                                                          |