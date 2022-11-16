#!/bin/bash
NIGHTLY_VERSION="nightly-2022-09-29"
REGEX="/$NIGHTLY_VERSION/d"
EXCESS_TOOLCHAINS="$(rustup toolchain list | sed '/(default)/d' | sed $REGEX | tr " " "\n")"
if ( test "$(echo $EXCESS_TOOLCHAINS | tr " " "\n" | wc -l)" -gt "1" ); then
    while IFS= read -r line; do 
        rustup toolchain uninstall $line
    done <<< "$EXCESS_TOOLCHAINS"
fi
