#version 460

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

struct AnimationData {
	uint frames;
	uint time;
};

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

layout(location = 0) uniform uint chunkIDIndex;
layout(location = 1) uniform uint commandIndexStart;
layout(location = 2) uniform uint size;
layout(location = 3) uniform bool isTransparent;
layout(location = 4) uniform bool onlyDrawPreviouslyInvisible;
layout(location = 5) uniform ivec3 playerPositionInteger;

layout(location = 6) uniform float lodDistance;

bool isVisible(int dir, ivec3 playerDist) {
	switch(dir) {
	case 0: // dirUp
		return playerDist.z >= 0;
	case 1: // dirDown
		return playerDist.z <= 0;
	case 2: // dirPosX
		return playerDist.x >= 0;
	case 3: // dirNegX
		return playerDist.x <= 0;
	case 4: // dirPosY
		return playerDist.y >= 0;
	case 5: // dirNegY
		return playerDist.y <= 0;
	}
	return true;
}

DrawElementsIndirectCommand addCommand(uint indices, uint vertexOffset, uint chunkID) {
	return DrawElementsIndirectCommand(indices, 1, 0, int(vertexOffset), chunkID);
}

void main() {
	uint chunkID = chunkIDs[chunkIDIndex + gl_GlobalInvocationID.x];
	if(gl_GlobalInvocationID.x >= size) return;
	if(isTransparent) {
		uint commandIndex = commandIndexStart + gl_GlobalInvocationID.x;
		if(chunks[chunkID].visibilityState != 0) {
			commands[commandIndex] = addCommand(chunks[chunkID].vertexCountTransparent, chunks[chunkID].vertexStartTransparent, chunkID);
		} else {
			commands[commandIndex] = DrawElementsIndirectCommand(0, 0, 0, 0, 0);
		}
		chunks[chunkID].visibilityState = 0;
	} else {
		uint commandIndex = commandIndexStart + gl_GlobalInvocationID.x*8;
		uint commandIndexEnd = commandIndex + 8;
		uint groupFaceOffset = 0;
		uint groupFaceCount = 0;
		uint oldoldvisibilityState = chunks[chunkID].oldVisibilityState;
		ivec3 playerDist = playerPositionInteger - chunks[chunkID].position.xyz;
		if(playerDist.x > 0) playerDist.x = max(0, playerDist.x - 32*chunks[chunkID].voxelSize);
		if(playerDist.y > 0) playerDist.y = max(0, playerDist.y - 32*chunks[chunkID].voxelSize);
		if(playerDist.z > 0) playerDist.z = max(0, playerDist.z - 32*chunks[chunkID].voxelSize);
		float playerDistSquare = dot(playerDist, playerDist);

		if((onlyDrawPreviouslyInvisible && chunks[chunkID].oldVisibilityState == 0 && chunks[chunkID].visibilityState != 0) || (chunks[chunkID].oldVisibilityState != 0 && !onlyDrawPreviouslyInvisible)) {
			for(int i = 0; i < 14; i++) {
				if(playerDistSquare >= lodDistance*lodDistance && i == 7) break;
				uint faceCount = chunks[chunkID].faceCountsByNormalOpaque[i];
				if(isVisible(i%7, playerDist) || faceCount == 0) {
					groupFaceCount += faceCount;
				} else {
					if(groupFaceCount != 0) {
						commands[commandIndex] = addCommand(6*groupFaceCount, chunks[chunkID].vertexStartOpaque + 4*groupFaceOffset, chunkID);
						commandIndex += 1;
						groupFaceOffset += groupFaceCount;
						groupFaceCount = 0;
					}
					groupFaceOffset += faceCount;
				}
			}
		}
		if(onlyDrawPreviouslyInvisible) {
			chunks[chunkID].oldVisibilityState = chunks[chunkID].visibilityState;
			chunks[chunkID].visibilityState = 0;
		}
		if(groupFaceCount != 0) {
			commands[commandIndex] = addCommand(6*groupFaceCount, chunks[chunkID].vertexStartOpaque + 4*groupFaceOffset, chunkID);
			commandIndex += 1;
		}

		for(; commandIndex < commandIndexEnd; commandIndex++) {
			commands[commandIndex] = DrawElementsIndirectCommand(0, 0, 0, 0, oldoldvisibilityState << 1 | chunks[chunkID].oldVisibilityState);
		}
	}
}
