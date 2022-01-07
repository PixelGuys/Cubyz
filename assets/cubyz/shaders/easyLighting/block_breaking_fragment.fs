#version 430

in vec2 outTexCoord;
in vec3 mvVertexPos;

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 position;

uniform sampler2D texture_sampler;

void main() {
	fragColor = texture(texture_sampler, outTexCoord);

	position = vec4(mvVertexPos, 1);
}
