#version 330

layout (location=0) in vec3 vertexPos;

out vec3 pos;

uniform mat4 viewMatrix;
uniform mat4 projectionMatrix;

void main() {
	gl_Position = projectionMatrix*viewMatrix*vec4(vertexPos, 1);

	pos = vertexPos;
}