#version 460

layout(location = 0) out vec3 mvVertexPos;
layout(location = 1) out vec3 boxPos;
layout(location = 2) flat out vec3 boxSize;

layout(location = 0) uniform mat4 projectionMatrix;
layout(location = 1) uniform mat4 viewMatrix;
layout(location = 2) uniform vec3 modelPosition;
layout(location = 3) uniform vec3 lowerBounds;
layout(location = 4) uniform vec3 upperBounds;

struct QuadInfo {
	vec3 normal;
	vec3 corners[4];
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

	vec3 vertexPos = quads[faceID].corners[vertexID] + quads[faceID].normal;
	vec4 mvPos = viewMatrix*vec4(lowerBounds + vertexPos*(upperBounds - lowerBounds) + modelPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
	boxPos = vertexPos*(upperBounds - lowerBounds);
	boxSize = upperBounds - lowerBounds;
}
