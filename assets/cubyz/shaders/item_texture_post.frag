#version 460

layout(location = 0) out vec4 fragColor;

layout(location = 0) in vec2 texCoords;

layout(binding = 3) uniform sampler2D color;

layout(location = 0) uniform bool transparent;

void main() {
	fragColor = texture(color, texCoords);
	if(transparent) {
		fragColor.a = 1;
		// TODO: Remove the background color. Somehow?
	}
	float maxColor = max(1.0, max(fragColor.r, max(fragColor.g, fragColor.b)));
	fragColor.rgb = fragColor.rgb/maxColor;
}
