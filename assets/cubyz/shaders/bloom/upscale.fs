#version 430

layout(location=0) out vec4 fragColor;

in vec2 texCoords;

layout(binding = 3) uniform sampler2D color;

void main() {
	fragColor = vec4(texture(color, texCoords).rgb, 1);
}