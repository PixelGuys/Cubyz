#version 460

layout(location = 0) in vec2 inTexCoords;

layout(location = 0) out vec2 texCoords;

void main() {
	texCoords = inTexCoords;
	gl_Position = vec4(inTexCoords*2 - vec2(1, 1), 0, 1);
}
