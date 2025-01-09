# Artifact - A Study of Undefined Behavior Across Foreign Function Boundaries in Rust Libraries

## Purpose
We are applying for all three badges. Our dataset, tool, and compilation scripts are all publicly **Available** on Zenodo. By following this script, you will confirm that our tool and data processing scripts are **Functional** and **Reusable** by reproducing the statistics in our paper and replicating our entire data collection process for a subset of the bugs that we discovered.

## Provenance
All materials relevant to this project are published on [Zenodo](https://doi.org/10.5281/zenodo.12727039) within an x86 Docker Image and in raw, uncompiled source.

A preprint of our paper is available at on [arXiv](https://arxiv.org/abs/2404.11671).

## Data
The artifact contains six files:

* `README.md` - This README file.

* `USAGE.md` - A guide on how to use and extend MiriLLI

* `DATASET.md` - Documentation on the contents of our dataset.

* `src.tar.gz` - the raw source code for our tool and data compliation scripts.

* `data.tar.gz` -  the raw output from our data collection steps described in Section 3 of our paper. 

* `crates.tar.gz` - the contents of the [crates.io](https://crates.io) database on 9/20/2023.

* `appendix.pdf` - the Appendix of our paper. 

* `preprint.pdf` - A preprint of our paper.

* `x86-docker-image.tar.gz` - an x86 Docker image containing a working build of our tool.

You will need `appendix.pdf`, `preprint.pdf`, `DATASET.md`, `USAGE.md`, and `x86-docker-image.tar.gz` for the evaluation.

### Data - Contents
Here we provide a brief overview of the contents of our docker image (excluding configuration files, `.renv` files, `.gitignore`, `Dockerfile`, `makefile`, etc.)
```
├── DATASET.md          // Documentation for our dataset and data compilation scripts.
├── USAGE.md            // Documentation on how to use and extend MiriLLI         
├── data.tar.gz         // The (compressed) dataset 
├── appendix.pdf        // The appendix
├── appendix            // LaTeX source for the appendix
├── rust-install        // Our custom Rust toolchain
├── rllvm-as            // A submodule containing a script for assembling LLVM bitcode
├── scripts             // R and Bash scripts for data collection and processing.
└── src                 // Source for early and late linting passes, which detected FFI bindings.
```
Our data collection took place over three stages using a variety of file formats and intermediate processing steps. We created comprehensive documentation for our dataset. For brevity, instead of including all 10 pages of documentation here, we provide it within `dataset/DATASET.md`. As part of evaluating the reusability of our tool, we will ask you to confirm that this documentation exists and answer a question about one part it. Here, though, we provide a brief summary its contents.
```
├── README.md           // Detailed documentation for the contents of each data collection step
├── bugs.csv            // A list of every bug we found and reported in our evaluation
├── bugs_excluded.csv   // Additional bugs that we found, but that had already been fixed, or are otherwise excluded
├── exclude.csv         // Crates that were excluded from out evaluation due to OOM errors during compilation
├── population.csv      // Every valid crate within the database. 
├── stage1              // Results from compiling every crate to find test cases with LLVM bitcode
├── stage2              // Results from running every test case in Miri to find which ones executed the FFI
└── stage3              // Results from running MiriLLI on each test case.
```

## Setup

To complete our evaluation, your system must meet the following requirements:
* An x86 System with [Docker](https://www.docker.com/) installed.
* 16 GB of RAM
* 100 GB of free space

We have set the resource requirements to be more than strictly necessary to ensure that you will not encounter any issues while evaluating the artifact.

To complete our evaluation, you will need:
1. A preprint of our paper
2. the Appendix
3. Our Docker image - `x86-docker-image.tar.gz`

Follow these instructions to ensure that you have access to these components. 

First, download the files `x86-docker-image.tar.gz` and `appendix.pdf` from [Zenodo](https://doi.org/10.5281/zenodo.12727039), and download our paper from [arXiv](https://arxiv.org/abs/2404.11671). 

Now, you can import our Docker image. This command should take ~10 minutes to complete.
```
# docker load -i x86-docker-image.tar.gz
```
To confirm that the image is functional, launch a new container and attach a shell. 
```
# docker run -it mirilli /bin/bash
```
Confirm that you have access to our custom Rust toolchain, `mirilli`, by executing the following command.
```
# rustup toolchain list
```
You should see the following output.
```
stable-x86_64-unknown-linux-gnu
nightly-2023-09-25-x86_64-unknown-linux-gnu
nightly-x86_64-unknown-linux-gnu
mirilli (default)
```
If all of these steps have been completed successfully, then you are ready to begin evaluating the artifact.

## Usage
Complete each of the following steps to evaluate our artifact. This assumes that you have successfully completed each of the steps shown in the previous section (**Setup**). Except for Step #1, all steps must be completed inside a Docker container launched from our image.

### Overview
* **Part 1** - *Check the Appendix* (5 human-minutes)
* **Part 2** - *Validate Results and Examples in the Paper* (50 human minutes + 20 compute minutes)
* **Part 3** - *Replicate Data Collection Steps* (20 human minutes, 45 compute minutes)
* **Part 4** - *How to Reuse Beyond the Paper* (10 human-minutes, 5 compute minutes)

As part of several steps, we will prompt you to input console commands and check that their output matches what is shown in this document. Commands are prefixed with a "#".

## Part 1 - Check the Appendix (5 human-minutes)

In this step, you will examine our Appendix to confirm that each of the sections we reference in our paper are present.

In Section III.B.a of our paper, we state the following:

> We provide a formal model of our value conversion functions in Section 2 of the Appendix.

**Task:** Open the Appendix and confirm that we provide this model by navigating to any of the subsections withiun Section 2.

At the end of the introduction to Section IV of our paper (Results) and immediately prior to Section IV.A, we state the following:

> We refer to each bug using a unique numerical ID corresponding to tables in Section 1 of the Appendix.

**Task:** Open the Appendix and navigate to Section 1, Table 2. Check to confirm that:
* There are 46 Bug IDs
* For every Bug ID, we include at least one link in at least one of the columns "Issues", "Pull(s)", or "Commits". 

You have now completed this step of our evaluation.

## Part 2 - Validate Results and Examples in the Paper (50 human minutes + 10 compute minutes)
The complete dataset is provided as part of our Docker image within the directory `dataset`. It is documented in the file `DATASET.md`.
In this stage, you will compile the dataset, examine its output, and compare it against several of the statistics shown in the paper to confirm that 
they can be replicated using our tool. This and each subsequent step requires our Docker image.

After launching a container, execute the following command to build our dataset. **This command will take 3-5 minutes to complete**
```
# DATASET=dataset make build
```
This will compile its contents from the `dataset` folder into the `build` folder. 

Confirm that this step has succeeded by executing the following command:

```
# tree -L 1 build/
```

You should see the following output.

```
├── stage1
├── stage2
├── stage3
├── stats.csv
├── stats_long.csv
└── visuals
```
To complete this step, you will be using the files `build/stats_long.csv` and `build/visuals/bug_counts_table.csv`.

### Part 2.1 - Inline Statistics - (20 human minutes, 5 compute minutes)
To validate this section, you will need to have a copy of the paper, this README, and the contents of the file `build/stats_long.csv`. This file contains two columns: `key` and `value`. Each value is a statistic, and each 
key is an identifier that links to both a table in DATASET.md and the CSV file `dataset/stat_key_descriptions.csv`. Each of these files describe the meaning of each statistic. 

Here, you will reproduce a subset of our inline statistics to confirm that they can be replicated from our dataset. 

Navigate to Section III.A of the paper ("Sampling") on page 6. Skim this section and find at least 1-3 of the quotes in the column "Quotes" of the table shown below. When you find a quote, look in the table for its corresponding "Key". Then, execute the following command with `[key]` replaced by the string under "Key". Confirm that the number shown on that line matches the statistic shown in the text.
```
grep -r "[key]," ./build/stats_long.csv
```

| Quote                                                   | Key |
|---------------------------------------------------------|---|
| It contained *125,804* unique crates                      | `num_crates_unfiltered`    |
| (*121,015*) had at least one valid published version. | `num_crates_all`    |
| (*84,106*) compiled without intervention.             | `num_crates_compiled`    |
| (*44,661*) had unit tests.                            | `num_crates_had_tests`    |
| (*11,120*) produced LLVM bitcode files                 | `num_crates_had_bytecode`    |
| (*3,785*) of crates with both unit tests and bitcode   | `num_crates_had_tests_and_bytecode`    |
| *88,637* tests that we identified                         | `test_count_overall`    |
| (*47,189*) passed                                     | `tests_passed`    |
| (*36,766*) failed                                     | `tests_failed`    |
| (*3,869*) timed out                                    | `tests_timed_out`    |
| (*1,178*) had been manually disabled                   | `tests_disabled`    |
| (*23,116*) had failed due to foreign function calls.  | `tests_failed_ffi`    |
| (*9,130*) called a foreign function we could execute. | `meta_llvmengaged`    |
| (*957*) of the crates with tests and bytecode         | `meta_crates_llvmengaged`    |

All of the inline statistics in Section III and IV were taken from this file, with a few exceptions.
At the end of Section III.A, we report on the percentage of crates with foreign function bindings. 
We collected these statistics by querying the database directly, using the output from building our
dataset. We have excluded this section from our replication to save time and reduce the size of our Docker image, which is already substantial to support building and testing each of these components. We provides these queries in `src/scripts/dependents.sql`.

### Part 2.2  - Section IV, Table I - (5 human minutes)
Navigate to Table 1, which is at the top of Page #7.
This table was generated manually from the CSV file `build/visuals/bug_counts_table.csv`. 
The layout of this file is a 1:1 match for the table.
View its contents by executing the following command:
```
# cat build/visuals/bug_counts_table.csv
```
Compare the numbers with the counts shown in the table to confirm that they match. 

### Part 2.3 - Figure 3 - (10 human minutes, 1 compute minute)
We provide a working version of this minimal example in the directory `demo/figures/3`.
To replicate the bug, navigate to this directory:
```
# cd /usr/src/mirilli/demo/figure3/
```
You can view the Rust source code for version of this example with the bug by executing the following command:
```
# cat src/bug.rs   
```
And the C source code with this command: 
```
# cat src/main.c
```
View each file to confirm that—together—these files match the example shown in Figure 3 (with the exception of `open_f` instead of `open`) with the lines highlighted in red still present.

Then, execute this example in MiriLLI
```
# cargo miri run -- bug
```
You should see the following output, indicating that Miri detected a bug.
```
error: Undefined Behavior: read access through <4326> at alloc2082[0x8] is forbidden
  --> src/bug.rs:23:9
   |
23 |         b.cache
   |         ^^^^^^^ read access through <4326> at alloc2082[0x8] is forbidden
   |
...
```

Now, view the version of the example that contains the fix by executing the following command:
```
# cat src/fix.rs
```
Confirm that it matches the example shown in figure 3 with the lines highlighted in red replaced with the lines highlighted in green.

Then, execute this example in MiriLLI
```
# cargo miri run -- fix 
```
This command should complete without an error.

### Part 2.4 - Figure 4 - (10 human minutes, 1 compute minute)
We provide a working version of this minimal example in the directory `demo/figures/3`.
To replicate the bug, navigate to this directory:
```
# cd /usr/src/mirilli/demo/figure4/
```
You can view the Rust source code for version of this example with the bug by executing the following command:
```
# cat src/bug.rs   
```
And the C source code with this command: 
```
# cat src/main.c
```
View each file to confirm that—together—these files match the example shown in Figure 4 with the lines highlighted in red still present.

Then, execute this example in MiriLLI
```
# cargo miri run -- bug
```
You should see the following output, indicating that Miri detected a bug.
```
---- Foreign Error Trace ----

@ %10 = load i32, ptr %9, align 8, !dbg !32

/usr/src/mirilli/demo/figure4/src/main.c:24:46
src/bug.rs:16:18: 16:48
-----------------------------

error: Undefined Behavior: read access through <4441> at alloc2114[0x0] is forbidden
...
```
Now, view the version of the example that contains the fix by executing the following command:
```
# cat src/fix.rs
```
Confirm that it matches the example shown in figure 4 with the lines highlighted in red replaced with the lines highlighted in green.

Then, execute this example in MiriLLI
```
# cargo miri run -- fix 
```
This command should complete without an error.

## Part 3 - Replicate Data Collection Steps - (20 human minutes, 45 compute minutes)

We evaluated our tool in three stages. 

* **Stage 1** - Find crates with unit tests that produce LLVM bitcode
* **Stage 2** - Find tests from these crates that call foreign functions
* **Stage 3** - Execute these tests in our custom dynamic analysis tool

The details of specific output files from each stage are documented in `DATASET.md`. Here, we focus on the describing the minimum requirements and necessary steps for finding bugs. 

Fully replicating each of these steps for every published crate would take several days and hundreds of dollars in compute. To save you time, instead of running a full evaluation, you will replicate these stages for a subset of the crates where we found bugs. 

For convenience, we provide a "large" and "small" subsets for replicating our steps. The "small" sample contains 3 of the 37 crates where we found bugs. We will use this sample to test our first and second stages of data collection. The "large" sample contains triggering test cases from 29 of the 37 crates where we found bugs. We exclude 8 crates from this sample because 7 no longer compile with this nightly version of the Rust toolchain, and one relies on a library that is installed as part of this docker image, so it no longer statically links by default. 

Collecting and parsing data requires creating a directory to hold intermediate results. This directory must contain a file `population.csv` with the columns `crate_name` and `version`, in that order. Each of `demo/large` and `demo/small` contains this file. 

To begin, navigate to the root directory: 
```
# cd /usr/src/mirilli
```
Make sure that the `build` directory has been deleted.
```
# rm -rf ./build
```
Execute the following command to view an example of the file `population.csv` for our `small` sample, which contains 3 crates.
```
# cat demo/small/population.csv
```
Note that in the actual dataset (`./dataset/population.csv`), this file contains each of the ~120,000 valid crates that were published at the time of writing. We parallelized this data collection process by splitting this CSV file into N partitions, with each partition executed on a separate machine.

### Part 3.1 - Stage 1 - (5 human minutes, 5 compute minutes)
In this stage, we compiled every public Rust crate to find ones with test cases that produced LLVM bitcode.

The script for executing this stage is `./scripts/stage1/run.sh`. Execute the following command to view its purpose and requirements:
```
# ./scripts/stage1/run.sh
```
Execute the following command to begin data collection. **This will take about 1 minute to complete.**
```
# ./scripts/stage1/run.sh demo/small
```
This will create the directory `demo/stage1`. Execute the following command to print its contents.
```
# tree demo/small/stage1 -L 1
```
You should see the following output:
```
demo/small/stage1
├── bytecode
├── early
├── has_bytecode.csv
├── late
├── status_comp.csv
├── status_download.csv
├── status_lint.csv
├── tests
└── visited.csv

4 directories, 5 files
```
Compile the raw data from Stage 1 using the following command:
```
# DATASET=demo/small make build/stage1
```
You should see the following output:
```
Starting Stage 1...
Processing early lint results...
Processing late lint results...
Processing test results...
Finished Stage 1
```
Execute the following command to confirm that this stage was successful.
```
# tree build/stage1
```
You should see the following output:
```
build/stage1
├── category_error_counts.csv
├── early_abis.csv
├── error_info.csv
├── error_locations.csv
├── finished_early.csv
├── finished_late.csv
├── had_ffi.csv
├── has_tests.csv
├── late_abis.csv
├── lint_info.csv
├── stage1.stats.csv
└── stage2.csv

0 directories, 12 files
```
Here, we're concerned with the file `stage2.csv`, which contains the list of crates that had unit tests and produced bytecode during their build process. Run the following command to validate that it contains the crate we tested.
```
# cat build/stage1/stage2.csv
```
You should see the following output:
```
bzip2,0.4.4
dec,0.4.8
librsync,0.2.3
```
This indicates that each of the 3 crates that we used as input to this step produced bytecode and had test cases that we can execute.
This file will be used as input to Stage 2.

### Part 3.2 - Stage 2 - (5 human minutes, 10 compute minutes)
In this data collection stage, we ran every test for crates where we found bytecode in an unmodified version of Miri to find tests that called foreign functions. 

The script for executing this stage is `./scripts/stage2/run.sh`. Execute the following command to view its purpose and requirements:
```
# ./scripts/stage2/run.sh
```
To complete data collection for this stage, execute the following command. **This will take ~5 minutes to complete**
```
# ./scripts/stage2/run.sh demo/small ./build/stage1/stage2.csv
```
This will compile and execute every test case found in the first stage. When running the script, you should have seen output like so:
```
...
Running read::tests::smoke3...
Exit code is 1
Miri found FFI call for read::tests::smoke3
...
FINISHED!
```
This will create the directory `demo/stage2`. Execute the following command to print its contents.
```
# tree demo/small/stage2 -L 1
```
If this step succeeded, you should see the following output:
```
demo/small/stage2
├── info
├── logs
├── status_download.csv
├── status_miri_comp.csv
├── status_rustc_comp.csv
├── tests.csv
└── visited.csv

2 directories, 5 files
```
Execute the following command to compile the dataset for this stage.
```
# DATASET=demo/small make ./build/stage2
```
You should see the following output:
```
Starting Stage 2...
Finished Stage 2
```
To confirm that this stage is successful, execute the following command:
```
# tree build/stage2/
```
You should see the following output (excluding the annotations)
```
build/stage2/
├── stage2-ignored.csv
├── stage2.stats.csv
├── stage3.csv
└── tests.csv

0 directories, 4 files
```
The file `stage3.csv` is typically used as input to Stage 3. It contains a list of each of the test cases that called foreign functions.

### Part 3.3 - Stage 3 - (10 human minutes, 30 compute minutes)
In this stage, we used MiriLLI to execute each of the tests that we found in Stage 2. We had to complete this stage twice; once for each memory mode (as described in Section III). 

The script for this stage is `./scripts/stage3/run.sh`. Execute it without arguments to see its description.
```
# ./scripts/stage3/run.sh
```
The third argument, `-z`, is optional. If provided, then MiriLLI is executed in the "zeroed" memory mode, which
zero-initializes all LLVM-allocated memory by default. We will only test the zeroed mode, since this is required
for replicating a subset of our bugs.

Instead of using data from the previous stage, we will use a subset of the test cases where we found bugs. This consists of 31 tests from 29 crates. 
We updated the underlying Rust toolchain that MiriLLI depends on to version 1.81.0 after we completed our evaluation, and a few crates no longer compile with this version. A few tests triggered multiple bugs—after we fixed one, another appeared—so we only include them once here. The test case for Bug #19 is no longer replicable, but Bug #20 is still replicable, and it is of the same nature from the same underlying library. We expect that this is due to a bug in our implementation. We will update our artifact if we find the root cause of this issue. We have documented each of these limitations in `dataset/bugs.csv`, 

Execute the following command to run the tests in zeroed mode. **This will take 20-30 minutes to complete**
```
# ./scripts/stage3/run.sh demo/large demo/large/stage3.csv -z
```
Execute the following command to view the output of this stage.
```
# tree demo/large/stage3/zeroed -L 1
```
You should see the following output:
```
demo/large/stage3/zeroed
├── crates
├── status_download.csv
├── status_miri_comp.csv
├── status_native_comp.csv
├── status_native.csv
├── status_stack.csv
├── status_tree.csv
└── visited.csv
```

Copy the output from this execution to an "uninit" directory, as if we had run that evaluation mode.
```
# cp -r demo/large/stage3/zeroed demo/large/stage3/uninit 
```
Now, compile the Stage 3 results with the following command:
```
# DATASET=demo/large make ./build/stage3
```
You should see the following output:
```
Starting Stage 3...
Processing errors from 'zeroed' mode...
Processing errors from 'uninit' mode...
Finished Stage 3
```
Confirm that this stage was successful by executing the following command:
```
# tree ./build/stage3 -L 1
```
You should see the following output:
```
./build/stage3
├── diff_errors_uninit.csv    // errors that only occurred in uninit mode
├── diff_errors_zeroed.csv    // errors that only occurred in zeroed mode
├── errors.csv                // all errors (not-deduplicated)
├── errors_unique.csv         // deduplicated errors
├── failures.csv              // tests that failed, under either mode
├── metadata.csv              // metadata flags set during run-time
├── stage3.stats.csv          // in-text statistics
├── uninit                    // Additional error information for each mode
└── zeroed  
```
To confirm that you have successfully reproduced our results, execute the following command:
```
# wc -l ./build/stage3/errors_unique.csv
```
You should see the following output, indicating that there were 30 unique errors (with one additional line for the CSV header).
```
31 ./build/stage3/errors_unique.csv
```
Execute the following command to see a sample of our results for the crate `dec`.
```
grep "dec," ./build/stage3/errors_unique.csv
```
You should see the following output:
```
dec,0.4.8,test_overloading,0,1,1,Using Uninitialized Memory...
dec,0.4.8,test_decimal128_special_value_coefficient,0,1,1,Borrowing Violation...
```
From this point onward, we manually investigated the results in the files `errors_unique.csv` and `diff_errors[uninit/zeroed].csv`, recreating errors locally using MiriLLI and reporting them to maintainers. 

You have now completed this stage of our evaluation.

## Part 4 - How to Reuse Beyond the Paper (20 human-minutes, 5 compute minutes)
The guide in Part 4 can be used to replicate our evaluation on any set of crates.

We provide two additional files that document our tool and dataset to help future evaluators replicate our results and extend our tool. As previously mentioned, we document the contents and structure of our dataset in detail within the file `DATASET.md`. The file `USAGE.md` provides a brief introduction to our toolchain, as well as steps for building our Docker image. It describes the configuration options that we added to Miri, which support the memory and initialization modes we describe in Section III.B of our paper. This file also provides a guide to extending and maintaining MiriLLI with links to relevant areas of our source code for each key component.

Our toolchain can still be used on recently published crates. The crate `bzip2` was at version 0.4.4 when we conducted our evaluation, but it has since been updated to verion 0.5.0, and ownership of the library has changed. However, the bug that we detected is still present. You can replicate it here, now, by following these steps. 

First, download the newest version of the library.
```
# cargo-download bzip2==0.5.0 -x -o bzip2 
```
Then, enter the directory and test it. Ensure that the current toolchain is set to `mirilli`.
```
# cd bzip2
# rustup override set mirilli
# cargo miri test -- bufread::tests::bug_61
```
You should see the following output for the test `bufread::tests::bug_61`, indicating a cross-language aliasing violation.
```
---- Foreign Error Trace ----

@ %250 = load i32, ptr %249, align 8, !dbg !379

.../bzip2-sys-0.1.11+1.0.8/bzip2-1.0.8/decompress.c:197:178
.../bzip2-1.0.8/bzlib.c:842:20
src/mem.rs:236:19: 236:62
-----------------------------

error: Undefined Behavior: attempting a read access using <186391> at alloc62307[0x8], but that tag does not exist in the borrow stack for this location
```
You have now completed our artifact evaluation.