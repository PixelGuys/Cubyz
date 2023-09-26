#!/bin/bash

version=zig-linux-x86_64-0.12.0-dev.596+2adb932ad

mkdir -p compiler/zig
touch compiler/version.txt
if [[ $(< compiler/version.txt) != "$version" ]]; then
    echo "Deleting old zig installation..."
    rm -r compiler/zig
    mkdir compiler/zig
    echo "Downloading zig version $version..."
    wget -O compiler/archive.tar.xz https://ziglang.org/builds/$version.tar.xz
    echo "Extracting tar file..."
    tar --xz -xf compiler/archive.tar.xz --directory compiler/zig --strip-components 1
    echo "Done."
    rm compiler/version.txt
    printf "$version" >> compiler/version.txt
fi

./compiler/zig/zig build run $@