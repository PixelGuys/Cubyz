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
