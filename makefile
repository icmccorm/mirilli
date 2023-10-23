.PHONY: default
default: all
.DEFAULT_GOAL := all
all: clean
	@(cd src/early && cargo build)
	@(cd src/late && cargo build)
	@(cargo dylint list)
clean:
	@(rm -rf ./test > /dev/null)
	@(rm -rf ./src/early/target)
	@(rm -rf ./src/late/target)
	@(rm -rf ./src/shared/target)
clean-cache:
	@(cargo install cargo-cache 1> /dev/null)
	@(cargo cache -a 1> /dev/null)
	@(./scripts/clean.sh)
rates:
	@(Rscript ./data/pass_rates.r)
extract: clean-compile
	./scripts/extract.sh
push:
	@./scripts/misc/list_instances.sh instances.csv
	@./scripts/misc/push.sh ./instances.csv
pull:
	@./scripts/misc/list_instances.sh ./instances.csv
	@./scripts/misc/pull.sh ./instances.csv

extract-stage1:
	@./scripts/stage1/extract.sh ./pulled
	@./scripts/stage1/extract_tests.sh

compile-stage1:
	@rm -rf ./data/compiled/stage1/*
	@mkdir -p ./data/compiled/stage1/lints
	@(python3 ./scripts/stage1/compile.py ./data/results/stage1 ./data/compiled/stage1/lints)
	@Rscript ./scripts/stage1/summarize.r

extract-stage2:
	@./scripts/stage2/extract.sh ./pulled

compile-stage2:
	@Rscript ./scripts/stage2/summarize.r

compile-stage3:
	python3 ./scripts/stage3/collate.py ./data/results
	