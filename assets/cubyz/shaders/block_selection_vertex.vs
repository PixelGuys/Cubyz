#version 430

layout (location=0)  in vec3 position;

out vec3 mvVertexPos;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 modelPosition;

void main() {
	vec4 mvPos = viewMatrix*vec4(position + modelPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	gl_Position.z -= 2e-4*gl_Position.w;
	mvVertexPos = mvPos.xyz;
}
