all:
	@(cd src/early && cargo build)
	@(cd src/late && cargo build)
	@(cargo dylint list)

clean-cache:
	@(cargo install cargo-cache 1> /dev/null)
	@(cargo cache -a 1> /dev/null)
	@(./scripts/clean.sh)

push:
	@./scripts/misc/list_instances.sh instances.csv
	@./scripts/misc/push.sh ./instances.csv

pull:
	@./scripts/misc/list_instances.sh ./instances.csv
	@./scripts/misc/pull.sh ./instances.csv

extract-stage1:
	@./scripts/stage1/extract.sh ./pulled
	@./scripts/stage1/extract_tests.sh

extract-stage2:
	@./scripts/stage2/extract.sh ./pulled
	
extract-stage3:
	@./scripts/stage3/extract.sh ./pulled ./results/stage3/uninit

summarize: ./build
	@Rscript ./scripts/summarize.r

validate: ./build
	@Rscript ./scripts/validate.r

visualize:
	@Rscript ./scripts/visualize.r


./build: ./build/stage1 ./build/stage2 ./build/stage3

./build/stage1:
	@echo "Starting Stage 1..."
	@rm -rf ./build/stage1
	@mkdir -p ./build/stage1
	@(python3 ./scripts/stage1/compile.py ./results/stage1 ./build/stage1)
	@Rscript ./scripts/stage1/summarize.r
	@echo "Finished Stage 1"

./build/stage2:
	@echo "Starting Stage 2..."
	@Rscript ./scripts/stage2/summarize.r
	@echo "Finished Stage 2"


./build/stage3:
	@echo "Starting Stage 3..."
	@python3 ./scripts/stage3/parse.py ./results/stage3/zeroed
	@python3 ./scripts/stage3/parse.py ./results/stage3/uninit
	@Rscript ./scripts/stage3/summarize.r
	@echo "Finished Stage 3"

clean:
	@rm -rf ./build

.PHONY: default
default: build
.DEFAULT_GOAL := build