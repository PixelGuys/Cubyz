#version 460

layout(early_fragment_tests) in;

layout(location = 0) flat in uint chunkID;

struct ChunkData {
	ivec4 position;
	vec4 minPos;
	vec4 maxPos;
	int voxelSize;
	uint lightStart;
	uint vertexStartOpaque;
	uint faceCountsByNormalOpaque[14];
	uint vertexStartTransparent;
	uint vertexCountTransparent;
	uint visibilityState;
	uint oldVisibilityState;
	uint visibilityStateDepth;
	uint oldVisibilityStateDepth;
};

layout(std430, binding = 6) buffer _chunks
{
	ChunkData chunks[];
};

layout(location = 4) uniform bool isDepth;

void main() {
	if(isDepth) {
		chunks[chunkID].visibilityStateDepth = 1;
	} else {
		chunks[chunkID].visibilityState = 1;
	}
}
