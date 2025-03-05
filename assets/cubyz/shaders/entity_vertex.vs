#version 430

out vec2 outTexCoord;
out vec3 mvVertexPos;
out vec3 outLight;
flat out vec3 normal;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 ambientLight;
uniform vec3 directionalLight;
uniform uint light;

struct QuadInfo {
	vec3 normal;
	vec3 corners[4];
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

	vec3 position = quads[faceID].corners[vertexID];

	vec4 mvPos = viewMatrix*vec4(position, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
	outTexCoord = quads[faceID].cornerUV[vertexID];
	outLight = calcLight(light);
}
