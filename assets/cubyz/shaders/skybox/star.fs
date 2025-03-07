#version 430

in vec3 pos;
in vec3 starPos;
in vec3 color;

uniform float starOpacity;

layout (location = 0, index = 0) out vec4 fragColor;

void main() {
	if (distance(pos, starPos) > 1.0/3.0)
		discard;

	fragColor = vec4(color * starOpacity, 1);
}
