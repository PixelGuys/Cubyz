#version 430

in vec3 pos;
in vec3 starPos;
in vec3 color;

layout (location = 0, index = 0) out vec4 fragColor;

void main() {
	if (dot(pos - starPos, pos - starPos) > 1.0/12.0)
		discard;

	fragColor = vec4(color, 1);
}
