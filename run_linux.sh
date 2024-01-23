#!/bin/bash

cd "$(dirname "$0")"

./debug_linux.sh -Doptimize=ReleaseFast "$@"

# export NO_PAUSE=1 may be used to silence this prompt
if [ ! $NO_PAUSE ]; then
	echo "Press enter key to continue. (Or export NO_PAUSE=1 to skip this prompt.)"
	read
fi
