#version 460

layout(location = 0) in vec3 position;

layout(location = 0) out vec3 mvVertexPos;

layout(location = 0) uniform mat4 projectionMatrix;
layout(location = 1) uniform mat4 viewMatrix;
layout(location = 2) uniform vec3 modelPosition;
layout(location = 3) uniform vec3 lowerBounds;
layout(location = 4) uniform vec3 upperBounds;

void main() {
	vec4 mvPos = viewMatrix*vec4(lowerBounds + position*(upperBounds - lowerBounds) + modelPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
}
