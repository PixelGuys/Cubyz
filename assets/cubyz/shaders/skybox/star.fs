#version 430

in vec3 color;

uniform float starOpacity;
uniform float starScale;

layout (location = 0, index = 0) out vec4 fragColor;

void main() {
	float starScaleOpacity = min(starScale, 1);
	fragColor = vec4(color * starOpacity * starScaleOpacity, 1);
}
