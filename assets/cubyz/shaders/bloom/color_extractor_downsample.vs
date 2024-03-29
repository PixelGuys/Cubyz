#version 430

layout (location=0)  in vec2 inTexCoords;

out vec2 texCoords;
out vec2 normalizedTexCoords;

layout(binding = 3) uniform sampler2D color;

void main() {
	normalizedTexCoords = inTexCoords;
	texCoords = inTexCoords*textureSize(color, 0) - 0.25;
	gl_Position = vec4(inTexCoords*2 - vec2(1, 1), 0, 1);
}