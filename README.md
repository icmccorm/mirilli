# Artifact - A Study of Undefined Behavior Across Foreign Function Boundaries in Rust Libraries

## Purpose
We are applying for all three badges. Our dataset, tool, and compilation scripts are all publicly **Available** on Zenodo. By following this script, you will confirm that our tool and data processing scripts are **Functional** and **Reusable** by reproducing the statistics in our paper and replicating our entire data collection process for one of the bugs we discovered. This bug still remains in the newest version of the library (published in December, 2024), so by following our evaluation, you will demonstrate that our tool is still functional and capable of finding bugs in libraries published since our evaluation.

## Provenance
All materials relevant to this project are published on [Zenodo](https://doi.org/10.5281/zenodo.12727039) within an x86 Docker Image and in raw, uncompiled source.

A preprint of our paper is available at on [arXiv](https://arxiv.org/abs/2404.11671).

## Data
The artifact published on Zenodo contains four files:

* `tool.raw.tar.gz` - (XXX MB) - the raw source code for our tool and data compliation scripts.

* `data.raw.tar.gz` - (XXX MB) - the contents of the [crates.io](https://crates.io) database on 9/20/2023 and the raw output from our data collection steps described in Section 3 of our paper. 

* `appendix.pdf` - (XXX MB) - the Appendix to our paper. 

* `docker-image.tar.gz` - (XXX GB) - a Docker image containing the contents of the previous files and a working build of our tool.

You will only need `appendix.pdf` and `docker-image.zip` for the evaluation; all other files can be ignored.

### Data - Contents
Here we provide a brief overview of the contents of our docker image (excluding configuration files, `.renv` files, `.gitignore`, `Dockerfile`, `makefile`, etc.)
```
├── README.md
├── dataset             // The dataset
    ├── crates-db       // The data dump from crates.io
    ├── DATASET.md      // High-level detail for each stage of data collection
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

We have set the resource requirements to be more than is strictly necessary to ensure that you will not encounter any issues while evaluating this artifact.

To complete our evaluation, you will need:
1. A preprint of our paper
2. the Appendix
3. Our docker image. 

Follow these instructions to ensure that you have access to these components. 

First, download the files `docker-image.zip` and `appendix.pdf` from [Zenodo](https://doi.org/10.5281/zenodo.12727039), and download our paper from [arXiv](https://arxiv.org/abs/2404.11671). 

Next, import our Docker image.
```
docker import docker-image.zip mirilli
```
To confirm that the image is functional, launch a new container and attach a shell. 
```
docker run mirilli -it /bin/bash
```
Confirm that you have access to our custom Rust toolchain, `mirilli`, by executing the following command.
```
rustup toolchain list
```
You should see the following output.
```
mirilli
```
If all of these steps have been completed successfully, then you are ready to begin evaluating the artifact.

## Usage
Complete each of the following steps to evaluate our artifact. This assumes that you have successfully completed each of the steps shown in the previous section (**Setup**). Except for Step #1, all steps must be completed inside a Docker container launched from our image.

### Overview
* **Step 1** - *Check the Appendix* (10 human-minutes)
* **Step 2** - *Validate Results in Paper* (30 human-minutes + 5 compute-minutes)
* **Step 3** - *Demonstrate Functionality & Reusability* (30 human minutes + 1 compute minute)

Starting here, the entire evaluation can be completed in under 90 minutes.

## Check the Appendix (10 human-minutes)

In this step, you will examine our Appendix to confirm that each of the sections we reference in our paper are present. We mention the Appendix twice in our paper, so completing this section involves two steps.

At the end of the introduction to Section IV of our paper (Results) and immediately prior to Section IV.A, we state the following:

> We refer to each bug using a unique numerical ID corresponding to tables in Section 1 of the Appendix.

Open the Appendix document and navigate to Section 1, Table 2. Check to confirm that for every Bug ID, we include at least one item in one of the columns "Issues", "Pull(s)", and "Commits". 

Later on in Section IV, we reference specific issues from two separate Rust crates: bzip2, and flate2. 
> 



## Validate Results in Paper (1 human-hour + 5 compute minutes)
In this step, you will 

## Tool Demonstration (15 human minutes + 5 compute minutes)

In this step, we will demonstrate that our tool is functional and reusable by walking through each
step of our data collection and bug-finding processes. 

To respect your time, instead of replicating the entire dataset, you will use a single crate, [`bzip2`](https://github.com/trifectatechfoundation/bzip2-rs), where we found a cross-language
aliasing violation. At the time of our data collection, the latest version of this crate was 0.4.4, and it was maintained by [Alex Crichton](https://github.com/alexcrichton). Ownership has since been transferred to the Trifecta Tech Foundation, which updated it to version 0.5.0 in December of 2024. This version eliminated several bugs and added a new Rust backend, but our bug still remains in the C backend. You will evaluate the functionality and reusability of our tool by walking through each stage of data collection for this library and replicating the aliasing bug in this library. This step-by-step walkthrough is intended to be used as a guide for anyone wishing to replicate our results in the future. 

### Stage 1 - 