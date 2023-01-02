.PHONY: default
default: all
.DEFAULT_GOAL := all
all:
	@(cd src/early && cargo build)
	@(cd src/late && cargo build)
	@(cargo dylint list)
clean:
	@(rm -rf ./test > /dev/null)
	@(rm -f all_sorted.csv)
	@(rm -f visited_sorted.csv)
clean-cache:
	@(cargo install cargo-cache 1> /dev/null)
	@(cargo cache -a 1> /dev/null)
	@(./scripts/clean.sh)
clean-compile:
	@(rm -f ./data/compiled/* 1> /dev/null)
compile: clean-compile
	@(python3 ./scripts/compile.py ./data/results ./data/compiled)
rates:
	@(Rscript ./data/pass_rates.r)
clean-sample:
	@(rm -f ./data/coding/samples/* 1> /dev/null)
sample: clean-sample
	@(Rscript ./data/sample.r)