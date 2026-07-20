#version 460

#include "chunk_data.glsl"

layout(early_fragment_tests) in;

layout(location = 0) flat in uint chunkID;

layout(location = 4) uniform bool isDepth;

void main() {
	if(isDepth) {
		chunks[chunkID].visibilityStateDepth = 1;
	} else {
		chunks[chunkID].visibilityState = 1;
	}
}
