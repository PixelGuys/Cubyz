#version 460

layout(location = 0) out vec2 outTexCoord;
layout(location = 1) out vec3 mvVertexPos;
layout(location = 2) out vec3 outLight;
layout(location = 3) flat out vec3 normal;

layout(location = 0) uniform mat4 projectionMatrix;
layout(location = 1) uniform mat4 viewMatrix;
layout(location = 2) uniform vec3 ambientLight;
layout(location = 3) uniform uint light;

struct QuadInfo {
	vec3 normal;
	float corners[4][3];
	vec2 cornerUV[4];
	uint textureSlot;
	int opaqueInLod;
};

layout(std430, binding = 11) buffer _quads
{
	QuadInfo quads[];
};

vec3 calcLight(uint fullLight) {
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
	return max(sunLight*ambientLight, blockLight)/31;
}

void main() {
	int faceID = gl_VertexID >> 2;
	int vertexID = gl_VertexID & 3;

	normal = quads[faceID].normal;

	vec3 position = vec3(quads[faceID].corners[vertexID][0], quads[faceID].corners[vertexID][1], quads[faceID].corners[vertexID][2]);

	vec4 mvPos = viewMatrix*vec4(position, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
	outTexCoord = quads[faceID].cornerUV[vertexID];
	outLight = calcLight(light);
}
