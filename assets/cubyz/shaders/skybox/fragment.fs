#version 330 

layout (location=0) out vec4 fragColor;

in vec3 pos;

void main() {
	fragColor = vec4(normalize(pos), 1);
}