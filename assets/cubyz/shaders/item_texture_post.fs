#version 430
out vec4 fragColor;

in vec2 texCoords;

uniform sampler2D color;
uniform bool transparent;

void main() {
	fragColor = texture(color, texCoords);
	if(transparent) {
		fragColor.a = 1;
		// TODO: Remove the background color. Somehow?
	}
	float maxColor = max(1.0, max(fragColor.r, max(fragColor.g, fragColor.b)));
	fragColor.rgb = fragColor.rgb/maxColor;
}
