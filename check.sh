#!/bin/bash
NUM_VISITED=$(wc -l < ./data/results/8/visited.csv); bc -l <<< "$NUM_VISITED/93477.0*100"