#!/bin/bash

cd "$(dirname "$0")"

./debug_linux.sh -Doptimize=ReleaseFast "$@"
