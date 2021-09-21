#version 330

layout (location=0) in vec3 vertexPos;
layout (location=1) in vec2 texCoords;

out vec2 outTexCoords;

uniform mat4 viewMatrix;
uniform mat4 projectionMatrix;

void main() {
	gl_Position = projectionMatrix*viewMatrix*vec4(vertexPos, 1);

	outTexCoords = texCoords;
}