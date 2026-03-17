#version 460

layout (location = 0) in vec3 inPos;
layout (location = 1) in vec3 inNormal;
layout (location = 2) in vec2 inUV;
layout (location = 3) in uint inTextureSlot;
layout (location = 4) in int inOpaqueInLod;

layout(location = 0) out vec2 outTexCoord;
layout(location = 1) out vec3 mvVertexPos;
layout(location = 2) out vec3 outLight;
layout(location = 3) flat out vec3 normal;

layout(location = 0) uniform mat4 projectionMatrix;
layout(location = 1) uniform mat4 viewMatrix;
layout(location = 2) uniform vec3 ambientLight;
layout(location = 3) uniform uint light;

vec3 square(vec3 x) {
	return x*x;
}

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
	return min(sqrt(square(sunLight*ambientLight) + square(blockLight)), vec3(31))/31;
}

void main() {
	normal = inNormal;

	vec4 mvPos = viewMatrix*vec4(inPos, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
	outTexCoord = inUV;
	outLight = calcLight(light);
}
