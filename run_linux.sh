#!/bin/bash

cd "$(dirname "$0")"

./debug_linux.sh -Doptimize=ReleaseSafe "$@"

if [ ! $NO_PAUSE ]; then
	echo "Press enter key to continue. (Or export NO_PAUSE=1 to skip this prompt.)"
	read
fi
