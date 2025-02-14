#version 430 

layout (location=0) out vec4 fragColor;

in vec3 pos;

uniform vec3 skyColor;

void main() {
	fragColor = vec4(skyColor, 1);
}