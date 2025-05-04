#version 460

layout(location = 0) out vec4 fragColor;

layout(location = 0) in vec2 outTexCoords;

layout(binding = 0, location = 1000) uniform sampler2D image;

void main() {
	fragColor = texture(image, outTexCoords);
}
