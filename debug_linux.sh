#!/bin/bash

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

# NOTE(blackedout): Tell the Vulkan loader where it can find the MoltenVK driver manifest file and
# the directory where it can find the layer manifest files.
# Documented at https://vulkan.lunarg.com/doc/view/latest/mac/LoaderDriverInterface.html (2025-10-26)
# and at https://vulkan.lunarg.com/doc/view/latest/windows/layer_configuration.html (2025-10-27)
if [ "$(uname)" = "Darwin" ]; then
	export VK_DRIVER_FILES=./zig-out/bin/MoltenVK_icd.json
	export VK_ADD_LAYER_PATH=./zig-out/bin
fi

./zig-out/bin/Cubyz
