#version 460

flat out uint chunkID;

struct ChunkData {
	ivec4 position;
	vec4 minPos;
	vec4 maxPos;
	int visibilityMask;
	int voxelSize;
	uint vertexStartOpaque;
	uint faceCountsByNormalOpaque[7];
	uint vertexStartTransparent;
	uint vertexCountTransparent;
	uint visibilityState;
	uint oldVisibilityState;
};

layout(std430, binding = 6) buffer _chunks
{
	ChunkData chunks[];
};
layout(std430, binding = 9) buffer _chunkIDs
{
	uint chunkIDs[];
};

vec3 vertexBuffer[24] = vec3[24](
	vec3(0, 1, 0),
	vec3(0, 1, 1),
	vec3(0, 0, 0),
	vec3(0, 0, 1),

	vec3(1, 0, 0),
	vec3(1, 0, 1),
	vec3(1, 1, 0),
	vec3(1, 1, 1),

	vec3(0, 0, 0),
	vec3(0, 0, 1),
	vec3(1, 0, 0),
	vec3(1, 0, 1),

	vec3(1, 1, 0),
	vec3(1, 1, 1),
	vec3(0, 1, 0),
	vec3(0, 1, 1),

	vec3(0, 1, 0),
	vec3(0, 0, 0),
	vec3(1, 1, 0),
	vec3(1, 0, 0),

	vec3(1, 1, 1),
	vec3(1, 0, 1),
	vec3(0, 1, 1),
	vec3(0, 0, 1)
);

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform ivec3 playerPositionInteger;
uniform vec3 playerPositionFraction;

void main() {
	uint chunkIDID = uint(gl_VertexID)/24u;
	uint vertexID = uint(gl_VertexID)%24u;
	chunkID = chunkIDs[chunkIDID];
	vec3 modelPosition = vec3(chunks[chunkID].position.xyz - playerPositionInteger) - playerPositionFraction;
	if(all(lessThan(modelPosition + chunks[chunkID].minPos.xyz*chunks[chunkID].voxelSize, vec3(0, 0, 0))) && all(greaterThan(modelPosition + chunks[chunkID].maxPos.xyz*chunks[chunkID].voxelSize, vec3(0, 0, 0)))) {
		chunks[chunkID].visibilityState = 1;
		gl_Position = vec4(-2, -2, -2, 1);
		return;
	}
	vec3 vertexPosition = modelPosition + (vertexBuffer[vertexID]*chunks[chunkID].maxPos.xyz + (1 - vertexBuffer[vertexID])*chunks[chunkID].minPos.xyz)*chunks[chunkID].voxelSize;
	gl_Position = projectionMatrix*viewMatrix*vec4(vertexPosition, 1);
}

