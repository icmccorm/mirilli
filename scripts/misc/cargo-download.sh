#!/bin/sh
if [ $# -ne 2 ]; then
    echo "Usage: cargo-download.sh <crate> <version>"
    exit 1
fi
rm -rf tmp-download || exit 1
mkdir tmp-download || exit 1
cd tmp-download || exit 1
curl -L https://crates.io/api/v1/crates/$1/$2/download | tar -xzf -
mv $1-$2 ../extracted
cd .. || exit 1
rm -rf tmp-download || exit 1
