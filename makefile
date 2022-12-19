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
cache-clean:
	@(cargo install cargo-cache 1> /dev/null)
	@(cargo cache -a 1> /dev/null)
	@(./clean.sh)