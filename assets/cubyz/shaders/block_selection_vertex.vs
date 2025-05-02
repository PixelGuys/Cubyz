#version 460

layout(location = 0) in vec3 position;

layout(location = 0) out vec3 mvVertexPos;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 modelPosition;
uniform vec3 lowerBounds;
uniform vec3 upperBounds;

void main() {
	vec4 mvPos = viewMatrix*vec4(lowerBounds + position*(upperBounds - lowerBounds) + modelPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
}
