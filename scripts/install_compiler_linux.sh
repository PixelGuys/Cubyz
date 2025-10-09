#!/bin/bash

fail () {
	exit 1
}

echo "Detecting Zig compiler..."

BASE_VERSION=$(< .zigversion)

case "$(uname -s)" in
"Darwin")
	OS=macos;;
*)
	OS=linux;;
esac

if [ -n $ARCH ]
then
	case "$(uname -m)" in
	"arm64" | "aarch64")
		ARCH=aarch64;;
	"arm*")
		ARCH=armv7a;;
	"amd64" | "x86_64")
		ARCH=x86_64;;
	"x86*")
		ARCH=x86;;
	*)
		echo "Machine architecture could not be recognized ($(uname -m)). Report this bug with the result of \`uname -m\` and your preferred Zig release name."
		echo "Defaulting architecture to x86_64."
		ARCH=x86_64;;
	esac
fi

VERSION=zig-$ARCH-$OS-$BASE_VERSION

mkdir -p compiler/zig
touch compiler/version.txt

CURRENT_VERSION=$(< compiler/version.txt)

if [[ "$CURRENT_VERSION" != "$VERSION" ]]; then
	echo "Your Zig is the wrong version."
	echo "Deleting current Zig installation..."
	rm -r compiler/zig
	mkdir compiler/zig
	echo "Downloading $VERSION..."
	wget -O compiler/archive.tar.xz https://github.com/PixelGuys/Cubyz-zig-versions/releases/download/$BASE_VERSION/"$VERSION".tar.xz
	if [ $? != 0 ]
	then
		echo "Failed to download the Zig compiler."
		fail
	fi
	echo "Extracting tar file..."
	tar --xz -xf compiler/archive.tar.xz --directory compiler/zig --strip-components 1
	rm compiler/archive.tar.xz
	echo "Patching lib/std/zig/render.zig..."
	wget -O compiler/zig/lib/std/zig/render.zig https://github.com/PixelGuys/Cubyz-std-lib/releases/download/$BASE_VERSION/render.zig
	echo "$VERSION" > compiler/version.txt
	echo "Done updating Zig."
else
	echo "Zig compiler is valid."
fi
