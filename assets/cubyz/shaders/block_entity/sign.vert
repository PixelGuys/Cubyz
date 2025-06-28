#version 460

layout(location = 0) out vec3 mvVertexPos;
layout(location = 1) out vec3 direction;
layout(location = 2) out vec3 light;
layout(location = 3) out vec2 uv;
layout(location = 4) flat out vec3 normal;

layout(location = 0) uniform vec3 ambientLight;
layout(location = 1) uniform mat4 projectionMatrix;
layout(location = 2) uniform mat4 viewMatrix;
layout(location = 3) uniform ivec3 playerPositionInteger;
layout(location = 4) uniform vec3 playerPositionFraction;
layout(location = 5) uniform int quadIndex;
layout(location = 6) uniform uvec4 lightData;
layout(location = 7) uniform ivec3 chunkPos;
layout(location = 8) uniform ivec3 blockPos;

struct QuadInfo {
	vec3 normal;
	float corners[4][3];
	vec2 cornerUV[4];
	uint textureSlot;
	int opaqueInLod;
};

layout(std430, binding = 4) buffer _quads
{
	QuadInfo quads[];
};

void main() {
	int faceID = gl_VertexID >> 2;
	int vertexID = gl_VertexID & 3;
	uint fullLight = lightData[vertexID];
	vec3 sunLight = vec3(
		fullLight >> 25 & 31u,
		fullLight >> 20 & 31u,
		fullLight >> 15 & 31u
	);
	vec3 blockLight = vec3(
		fullLight >> 10 & 31u,
		fullLight >> 5 & 31u,
		fullLight >> 0 & 31u
	);
	light = max(sunLight*ambientLight, blockLight)/31;

	vec3 position = vec3(blockPos);

	normal = quads[quadIndex].normal;

	position += vec3(quads[quadIndex].corners[vertexID][0], quads[quadIndex].corners[vertexID][1], quads[quadIndex].corners[vertexID][2]);
	position += vec3(chunkPos - playerPositionInteger);
	position -= playerPositionFraction;

	direction = position;

	vec4 mvPos = viewMatrix*vec4(position, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
	vec2 maxUv = quads[quadIndex].cornerUV[0];
	vec2 minUv = quads[quadIndex].cornerUV[0];
	for(int i = 1; i < 4; i++) {
		maxUv = max(maxUv, quads[quadIndex].cornerUV[i]);
		minUv = min(minUv, quads[quadIndex].cornerUV[i]);
	}
	uv.x = (quads[quadIndex].cornerUV[vertexID].x == maxUv.x) ? 1 : 0;
	uv.y = (quads[quadIndex].cornerUV[vertexID].y == maxUv.y) ? 1 : 0;
}
