#!/bin/bash

cd "$(dirname "$0")"

fail () {
	exit 1
}

if ! ./scripts/detect_compiler_linux.sh
then
	fail
fi

echo "Building Zig Cubyz ($@) from source. This may take a few minutes..."

./compiler/zig/zig build "$@"

if [ $? != 0 ]
then
	fail
fi

echo "Cubyz successfully built!"
echo "Launching Cubyz."

./zig-out/bin/Cubyzig
