dylint: 
	
push:
	@./scripts/misc/list_instances.sh instances.csv
	@./scripts/misc/push.sh ./instances.csv

pull:
	@./scripts/misc/list_instances.sh ./instances.csv
	@./scripts/misc/pull.sh ./instances.csv

extract-stage1:
	@./scripts/stage1/extract.sh ${DATASET} ./pulled

extract-stage2:
	@./scripts/stage2/extract.sh ${DATASET} ./pulled
	
extract-stage3-uninit:
	@./scripts/stage3/extract.sh ${DATASET}/stage3/uninit ./pulled 

extract-stage3-zeroed:
	@./scripts/stage3/extract.sh ${DATASET}/stage3/zeroed ./pulled 

summarize:
	@Rscript ./scripts/summarize.r

validate: ./build
	@Rscript ./scripts/validate.r

build: ./build/stage1 ./build/stage2 ./build/stage3 summarize

./build/stage1:
	@echo "Starting Stage 1..."
	@rm -rf ./build/stage1
	@mkdir -p ./build/stage1
	@(python3 ./scripts/stage1/compile.py ${DATASET}/stage1 ./build/stage1)
	@Rscript ./scripts/stage1/summarize.r
	@echo "Finished Stage 1"

./build/stage2:
	@echo "Starting Stage 2..."
	@python3 ./scripts/stage2/compile.py ${DATASET}/stage2/logs ./build/stage2/
	@Rscript ./scripts/stage2/summarize.r
	@echo "Finished Stage 2"

./build/stage3:
	@echo "Starting Stage 3..."
	@python3 ./scripts/stage3/compile.py ${DATASET}/stage3/zeroed ./build/stage3/zeroed
	@python3 ./scripts/stage3/compile.py ${DATASET}/stage3/uninit ./build/stage3/uninit
	@Rscript ./scripts/stage3/summarize.r
	@echo "Finished Stage 3"

clean:
	@rm -rf ./build

.PHONY: default
default: build
.DEFAULT_GOAL := build