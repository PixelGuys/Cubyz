#version 460

layout(location = 0) flat out uint chunkID;

#include "chunk_data.glsl"

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

layout(location = 0) uniform mat4 projectionMatrix;
layout(location = 1) uniform mat4 viewMatrix;
layout(location = 2) uniform ivec3 playerPositionInteger;
layout(location = 3) uniform vec3 playerPositionFraction;
layout(location = 4) uniform bool isDepth;

void main() {
	uint chunkIDID = uint(gl_VertexID)/24u;
	uint vertexID = uint(gl_VertexID)%24u;
	chunkID = chunkIDs[chunkIDID];
	vec3 modelPosition = vec3(chunks[chunkID].position.xyz - playerPositionInteger) - playerPositionFraction;
	vec3 margin = vec3(1); // Avoid near plane clipping when the player is at the edge of chunks
	if(all(lessThan(modelPosition + chunks[chunkID].minPos.xyz*chunks[chunkID].voxelSize, margin)) && all(greaterThan(modelPosition + chunks[chunkID].maxPos.xyz*chunks[chunkID].voxelSize, -margin))) {
		if(isDepth) {
			chunks[chunkID].visibilityStateDepth = 1;
		} else {
			chunks[chunkID].visibilityState = 1;
		}
		gl_Position = vec4(-2, -2, -2, 1);
		return;
	}
	vec3 vertexPosition = modelPosition + (vertexBuffer[vertexID]*chunks[chunkID].maxPos.xyz + (1 - vertexBuffer[vertexID])*chunks[chunkID].minPos.xyz)*chunks[chunkID].voxelSize;
	gl_Position = projectionMatrix*viewMatrix*vec4(vertexPosition, 1);
}
