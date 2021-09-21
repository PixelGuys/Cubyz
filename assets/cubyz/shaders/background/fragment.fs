#version 330 

layout (location=0) out vec4 fragColor;

in vec2 outTexCoords;

uniform sampler2D image;

void main() {
	fragColor = texture(image, outTexCoords);
}