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
clean-compile:
	@(rm -f ./data/compiled/* 1> /dev/null)
	@(rm -f ./data/abi_subset.csv 1> /dev/null)
compile: clean-compile
	@(python3 ./scripts/compile.py ./data/results ./data/compiled)
	@(Rscript ./scripts/extract_abi_subset.r 1> /dev/null)
	@(Rscript ./scripts/extract_miri_tests.r 1> /dev/null)
rates:
	@(Rscript ./data/pass_rates.r)
extract: clean-compile
	./scripts/extract.sh
push:
	@./list_instances.sh instances.csv
	@./push.sh ./instances.csv
pull:
	@./list_instances.sh ./instances.csv
	@./pull.sh ./instances.csv