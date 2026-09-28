#version 460

#include "frame_uniforms.glsl"

layout(location = 0) in vec3 vertexPos;
layout(location = 1) in vec2 texCoords;

layout(location = 0) out vec2 outTexCoords;

void main() {
	gl_Position = projectionMatrix*viewMatrix*vec4(vertexPos, 1);

	outTexCoords = texCoords*vec2(1, -1);
}
