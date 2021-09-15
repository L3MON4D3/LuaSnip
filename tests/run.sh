#!/usr/bin/env bash

HERE="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
cd "$HERE/.."

init=tests/minimal_init.lua
dir=tests

nvim --headless --noplugin -u "$init" \
    -c "PlenaryBustedDirectory $dir { minimal_init = '$init' }"
