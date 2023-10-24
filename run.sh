#!/bin/bash

BASE_VERSION=$(< .zig-version)
VERSION=zig-linux-x86_64-$BASE_VERSION

mkdir -p compiler/zig
touch compiler/version.txt

CURRENT_VERSION=$(< compiler/version.txt)

if [[ "$CURRENT_VERSION" != "$VERSION" ]]; then
	echo "Deleting old zig installation..."
	rm -r compiler/zig
	mkdir compiler/zig
	echo "Downloading $VERSION..."
	wget -O compiler/archive.tar.xz https://ziglang.org/builds/"$VERSION".tar.xz
	echo "Extracting tar file..."
	tar --xz -xf compiler/archive.tar.xz --directory compiler/zig --strip-components 1
	echo "Done."
	rm compiler/archive.tar.xz
	echo "$VERSION" > compiler/version.txt
fi

./compiler/zig/zig build run "$@"