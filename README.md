# Artifact - A Study of Undefined Behavior Across Foreign Function Boundaries in Rust Libraries

## Purpose
We are applying for all three badges. Our dataset, tool, and compilation scripts are all publicly **Available** on Zenodo. By following this script, you will confirm that our tool and data processing scripts are **Functional** and **Reusable** by reproducing the statistics in our paper and replicating our entire data collection process for one of the bugs we discovered. This bug still remains in the newest version of the library, which was published in December, 2024. By following these steps, you will demonstrate that our tool is still functional and capable of finding bugs in libraries published since our evaluation.

## Provenance
All materials relevant to this project are published on [Zenodo](https://doi.org/10.5281/zenodo.12727039) within an x86 Docker Image and in raw, uncompiled source.

A preprint of our paper is available at on [arXiv](https://arxiv.org/abs/2404.11671).

## Data
The artifact contains four files:

* `tool.raw.tar.gz` - (XXX MB) - the raw source code for our tool and data compliation scripts.

* `data.raw.tar.gz` - (XXX MB) - the contents of the [crates.io](https://crates.io) database on 9/20/2023 and the raw output from our data collection steps described in Section 3 of our paper. 

* `appendix.pdf` - (XXX MB) - the Appendix of our paper. 

* `docker-image.tar.gz` - (XXX GB) - a Docker image containing the contents of the previous files and a working build of our tool.

You will only need `appendix.pdf` and `docker-image.tar.gz` for the evaluation.

### Data - Contents
Here we provide a brief overview of the contents of our docker image (excluding configuration files, `.renv` files, `.gitignore`, `Dockerfile`, `makefile`, etc.)
```
├── README.md           // This evaluations cript
├── DATASET.md          // Documentation for our dataset and data compilation scripts.
├── USAGE.md            // Documentation on how to use and extend MiriLLI
├── dataset             // The dataset
    ├── crates-db       // The data dump from crates.io
    ├── ...             
├── appendix.pdf        // The appendix
├── appendix            // LaTeX source for the appendix
├── mirilli-rust        // Our custom Rust toolchain (containing the source for MiriLLI)
├── rllvm-as            // A submodule containing a script for assembling LLVM bitcode
├── scripts             // R and Bash scripts for data collection and processing.
└── src                 // Source for early and late linting passes, which detected FFI bindings.
```
Our data collection took place over three stages using a variety of file formats and intermediate processing steps. We created comprehensive documentation for our dataset. For brevity, instead of including all 10 pages of documentation here, we provide it within `dataset/DATASET.md`. As part of evaluating the reusability of our tool, we will ask you to confirm that this documentation exists and answer a question about one part it. Here, though, we provide a brief summary its contents.
```
├── README.md           // Detailed documentation for the contents of each data collection step
├── bugs.csv            // A list of every bug we found and reported in our evaluation
├── bugs_excluded.csv   // Additional bugs that we found, but that had already been fixed, or are otherwise excluded
├── crates-db           // A snapshot of the crates.io database taken on 9/20/2023
├── exclude.csv         // Crates that were excluded from out evaluation due to OOM errors during compilation
├── population.csv      // Every valid crate within the database. 
├── stage1              // Results from compiling every crate to find test cases with LLVM bitcode
├── stage2              // Results from running every test case in Miri to find which ones executed the FFI
└── stage3              // Results from running MiriLLI on each test case.
```

## Setup
*This will take 60 minutes to complete.*

To complete our evaluation, your system must meet the following requirements:
* [Docker](https://www.docker.com/) installed.
* 16 GB of RAM
* 100 GB of free space

We have set the resource requirements to be more than strictly necessary to ensure that you will not encounter any issues while evaluating the artifact.

To complete our evaluation, you will need:
1. A preprint of our paper
2. the Appendix
3. Our Docker image - `docker-image.tar.gz`

Follow these instructions to ensure that you have access to these components. 

First, download the files `docker-image.tar.gz` and `appendix.pdf` from [Zenodo](https://doi.org/10.5281/zenodo.12727039), and download our paper from [arXiv](https://arxiv.org/abs/2404.11671). 

---
**Only for M-Series Mac Users, skip otherwise**

If you are using a Mac with an M-series processor, make sure that you have Rosetta enabled and installed by executing the following command: 

```
softwareupdate --install-rosetta --agree-to-license
```
Then, if you are using Docker Desktop, navigate to "Settings > General > Virtual Machine Options". Make sure that "Use Apple Virtualization Framework" is selected, and that you have checked "Use Rosetta for x86_64/amd64 emulation on Apple Silicon"

---

Now, you can import our Docker image. This command should take ~15 minutes to complete.
```
docker import docker-image.tar.gz mirilli
```
To confirm that the image is functional, launch a new container and attach a shell. 
```
docker run --platform linux/amd64 -it mirilli /bin/bash
```
Confirm that you have access to our custom Rust toolchain, `mirilli`, by executing the following command.
```
rustup toolchain list
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
* **Step 1** - *Check the Appendix* (10 human-minutes)
* **Step 2** - *Validate Results in Paper* (30 human-minutes + 5 compute-minutes)
* **Step 3** - *Review Documentation* (10 human-minutes)
* **Step 4** - *Demonstrate Functionality & Reusability* (30 human minutes + 5 compute minutes)

The entire evaluation can be completed in under 90 minutes starting from this point. Each step can be completed independent of the other steps.

## Check the Appendix (10 human-minutes)

In this step, you will examine our Appendix to confirm that each of the sections we reference in our paper are present.

In Section III.B.a of our paper, we state the following:

> We provide a formal model of our value conversion functions in Section 2 of the Appendix.

**Task:** Open the Appendix and confirm that we provide this model by navigating to any of the subsections withiun Section 2.

At the end of the introduction to Section IV of our paper (Results) and immediately prior to Section IV.A, we state the following:

> We refer to each bug using a unique numerical ID corresponding to tables in Section 1 of the Appendix.

**Task:** Open the Appendix and navigate to Section 1, Table 2. Check to confirm that:
* There are 47 Bug IDs
* For every Bug ID, we include at least one link in at least one of the columns "Issues", "Pull(s)", or "Commits". 
* Choose any link at random from one of these columns and confirm that it is valid. 

You have now completed this step of our evaluation.

## Validate Results in Paper (1 human-hour + 5 compute minutes)
The complete dataset is provided as part of our Docker image within the directory `dataset`. This c
## Tool Demonstration (15 human minutes + 5 compute minutes)

Here, you will demonstrate that our tool is functional and reusable by walking through each
step of our data collection and bug-finding processes. 
Fully replicating our dataset would take several days and more than a thousand dollars in compute. 
Instead, you will only compile a subset of the crates that we found. 

The details of specific output files are documented in `DATASET.md`. Here, we focus on the describing the minimum requirements and necessary steps for finding bugs. 

Our data collection process has three stages.

* Stage 1 - Find crates with unit tests that produce LLVM bitcode
* Stage 2 - Find tests from these crates that call foreign functions
* Stage 3 - Execute these tests in our custom dynamic analysis tool

Fully replicating each of these steps for every published crate would take several days and hundreds of dollars in compute. Instead, you will replicate these Stages for the 37 crates where we found bugs. 

Collecting and parsing data requires creating a directory to hold intermediate results. This directory must contain a file `population.csv` with two unlabelled columns holding the name and version of each crate that needs to be tested. For this demonstration, we have created one for you: `demo`.

Execute the following command to view an example of the file `population.csv`, which contains our sample of 37 crates.
```
$ cat demo/population.csv
```
Note that in the actual dataset (`./dataset/population.csv`), this file contains each of the ~120,000 valid crates that were published at the time of writing. We parallelized this data collection process by splitting this CSV file into N partitions, with each partition executed on a separate machine.

### Stage 1 - ()
In this stage, we compiled every public Rust crate to find ones with test cases that produced LLVM bitcode.
The script for executing this stage is `./scripts/stage1/run.sh`. Execute the following command to view its purpose and requirements:
```
$ ./scripts/stage1/run.sh
```
Execute the following command to collect data for `bzip2`.
```
$ ./scripts/stage1/run.sh demo
```
This will create the directory `demo/stage1`. Execute the following command to print its contents.
```
$ tree demo/stage1 | tail -n 1
```
If this step succeeded, you should see the following output (minus the annotations):
```
4 directories, 9 files
```
Compile the Stage 1 results using the following command:
```
$ DATASET=demo make build/stage1
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
$ tree build/stage1 | tail -n 1
```
You should see the following output:
```
0 directories, 11 files
```
Here, we're concerned with the file `stage2.csv`, which contains the list of crates that had unit tests and produced bytecode during their build process. Run the following command to validate that it contains the crate we tested.
```
> cat build/stage1/stage2.csv
```
You should see the following output:
```
bzip2,0.4.4
```
This file will be used as input to Stage 2.

### Stage 2

In this data collection stage, we ran every test for crates where we found bytecode in an unmodified version of Miri to find tests that called foreign functions. 

The script for executing this stage is `./scripts/stage2/run.sh`. Execute the following command to view its purpose and requirements:
```
$ ./scripts/stage2/run.sh
```
To complete data collection for this stage, execute the following command. 
```
$ ./scripts/stage2/run.sh demo ./build/stage1/stage2.csv
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
$ tree demo/stage2 -L 1
```
If this step succeeded, you should see the following output:
```
demo/stage2
├── logs
├── status_download.csv
├── status_miri_comp.csv
├── status_rustc_comp.csv
├── tests.csv
└── visited.csv
```
Execute the following command to compile the dataset for this stage.
```
$ DATASET=demo make ./build/stage2
```
You should see the following output:
```
Starting Stage 2...
Finished Stage 2
```
To confirm that this stage is successful, execute the following command:
```
$ tree build/stage2/
```
You should see the following output (excluding the annotations)
```
├── stage2-ignored.csv      // tests that were manually `#[ignore]`-ed
├── stage2.stats.csv        // in-text statistics
├── stage3.csv              // tests that encountered FFI calls
└── tests.csv               // all tests ran during this stage
```

The file `stage3.csv` will be used as input to Stage 3.

# Stage 3
In this stage, we used MiriLLI to execute each of the tests that we found in Stage 2.
We had to complete this stage twice; once for each memory mode (as described in Section III). 

The script for this stage is `./scripts/stage3/run.sh`. Execute it without arguments to see its description.

The third argument, `-z`, is optional. If provided, then MiriLLI is executed in the "zeroed" memory mode, which
zero-initializes all LLVM-allocated memory by default. 

Execute the following commands to run the tests we collected in MiriLLI.
```
$ ./scripts/stage3/run.sh demo build/stage2/stage3.csv
$ ./scripts/stage3/run.sh demo build/stage2/stage3.csv -z
```

Execute the following command to view the output.

```
$ tree demo/stage3 -L 1
```

You should see two directories; one for each memory mode:
```
demo/stage3/
├── uninit
└── zeroed
```

Execute the following command for each directory:
```
$ tree demo/stage3/uninit

```