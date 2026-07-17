#version 460

layout(early_fragment_tests) in;

layout(location = 0) flat in uint chunkID;

#include "chunk_data.glsl"

void main() {
	if(isDepth) {
		chunks[chunkID].visibilityStateDepth = 1;
	} else {
		chunks[chunkID].visibilityState = 1;
	}
}
