#!/usr/bin/env bash

cd "$(dirname "$0")"

fail () {
	exit 1
}

if ! ./scripts/install_compiler_linux.sh
then
	echo Failed to install Zig compiler.
	fail
fi

echo "Building Zig Cubyz ($@) from source. This may take a few minutes..."

./compiler/zig/zig build --error-style minimal "$@"

if [ $? != 0 ]
then
	fail
fi

echo "Cubyz successfully built!"
echo "Launching Cubyz."

if [ "$(uname)" = "Darwin" ]; then
    ./zig-out/bin/Cubyz.app/Contents/MacOS/Cubyz
else
    ./zig-out/bin/Cubyz
fi
