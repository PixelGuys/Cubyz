#version 430

in vec3 mvVertexPos;

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 position;

void main() {
	fragColor = vec4(0, 0, 0, 1);
	fragColor.rgb /= 4;

	position = vec4(mvVertexPos, 1);
}
