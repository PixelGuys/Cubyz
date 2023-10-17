#!/bin/bash

version=zig-linux-x86_64-0.12.0-dev.983+78f2ae7f2

mkdir -p compiler/zig
touch compiler/version.txt
if [[ $(< compiler/version.txt) != "$version" ]]; then
	echo "Deleting old zig installation..."
	rm -r compiler/zig
	mkdir compiler/zig
	echo "Downloading $version..."
	wget -O compiler/archive.tar.xz https://ziglang.org/builds/$version.tar.xz
	echo "Extracting tar file..."
	tar --xz -xf compiler/archive.tar.xz --directory compiler/zig --strip-components 1
	echo "Done."
	rm compiler/archive.tar.xz
	rm compiler/version.txt
	printf "$version" >> compiler/version.txt
fi

./compiler/zig/zig build run $@