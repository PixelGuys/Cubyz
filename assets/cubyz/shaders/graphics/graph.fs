#version 430

layout (location=0) out vec4 frag_color;

uniform vec3 lineColor;

void main() {
	frag_color = vec4(lineColor, 1);
}