#!/bin/bash
docker run -v /Users/icmccorm/git/ffickle/data:/usr/src/ffickle/link --cpus=4 --memory=6G ffickle:init ./verify.sh 1 /usr/src/ffickle/link