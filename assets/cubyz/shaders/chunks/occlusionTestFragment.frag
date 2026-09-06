#version 460

#include "chunk_data.glsl"

layout(early_fragment_tests) in;

layout(location = 0) flat in uint chunkID;

void main() {
	chunks[chunkID].visibilityState = 1;
}
