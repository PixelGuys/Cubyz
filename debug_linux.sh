#!/bin/bash

cd "$(dirname "$0")"

fail () {
    echo "Press enter key to continue."
    read
    exit 1
}

echo "Detecting Zig compiler..."

BASE_VERSION=$(< .zig-version)
VERSION=zig-macos-aarch64-$BASE_VERSION

mkdir -p compiler/zig
touch compiler/version.txt

CURRENT_VERSION=$(< compiler/version.txt)

if [[ "$CURRENT_VERSION" != "$VERSION" ]]; then
    echo "Your Zig is the wrong version."
	echo "Deleting current Zig installation..."
	rm -r compiler/zig
	mkdir compiler/zig
	echo "Downloading $VERSION..."
	wget -O compiler/archive.tar.xz https://ziglang.org/builds/"$VERSION".tar.xz
    if [ $? != 0 ]
    then
        echo "Failed to download the Zig compiler."
        fail
    fi
	echo "Extracting tar file..."
	tar --xz -xf compiler/archive.tar.xz --directory compiler/zig --strip-components 1
	rm compiler/archive.tar.xz
	echo "$VERSION" > compiler/version.txt
	echo "Done updating Zig."
else
    echo "Zig compiler is valid."
fi

echo "Building Cubyzig from source. This may take up to 10 minutes..."

./compiler/zig/zig build "$@"

if [ $? != 0 ]
then
    echo "Failed to build Cubyz."
    fail
fi

echo "Cubyz successfully built!"
echo "Launching Cubyz."

./compiler/zig/zig build run "$@"
