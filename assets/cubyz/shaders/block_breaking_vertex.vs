#version 430

layout (location=0)  in vec3 position;
layout (location=1)  in vec2 texCoord;
layout (location=2)  in vec3 vertexNormal;

out vec2 outTexCoord;
out vec3 mvVertexPos;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 modelPosition;

void main() {
	vec4 mvPos = viewMatrix*vec4(position + modelPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	outTexCoord = texCoord;
	mvVertexPos = mvPos.xyz;
}
