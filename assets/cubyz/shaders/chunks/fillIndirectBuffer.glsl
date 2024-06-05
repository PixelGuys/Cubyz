#version 430

layout (local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

struct AnimationData {
	uint frames;
	uint time;
};

struct ChunkData {
	ivec4 position;
	int visibilityMask;
	int voxelSize;
	uint vertexStartOpaque;
	uint vertexCountOpaque;
	uint vertexStartTransparent;
	uint vertexCountTransparent;
};
layout(std430, binding = 6) buffer _chunks
{
	ChunkData chunks[];
};
struct DrawElementsIndirectCommand {
	uint  count;
	uint  instanceCount;
	uint  firstIndex;
	int  baseVertex;
	uint  baseInstance;
};
layout(std430, binding = 8) buffer _commands
{
	DrawElementsIndirectCommand commands[];
};
layout(std430, binding = 9) buffer _chunkIDs
{
	uint chunkIDs[];
};

uniform uint chunkIDIndex;
uniform uint commandIndexStart;
uniform uint size;
uniform bool isTransparent;

void main() {
	uint chunkID = chunkIDs[chunkIDIndex + gl_GlobalInvocationID.x];
	uint commandIndex = commandIndexStart + gl_GlobalInvocationID.x;
	if(gl_GlobalInvocationID.x >= size) return;
	if(isTransparent) {
		commands[commandIndex] = DrawElementsIndirectCommand(
			chunks[chunkID].vertexCountTransparent,
			1,
			0,
			int(chunks[chunkID].vertexStartTransparent),
			chunkID
		);
	} else {
		commands[commandIndex] = DrawElementsIndirectCommand(
			chunks[chunkID].vertexCountOpaque,
			1,
			0,
			int(chunks[chunkID].vertexStartOpaque),
			chunkID
		);
	}
}
