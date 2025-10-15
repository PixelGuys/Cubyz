#version 460

layout (location = 0) in vec2 texCoord;
layout (location = 1) uniform float celestialOpacity;
layout (location = 2) uniform vec3 celestialColor;

layout(binding = 0) uniform sampler2D celestialTexture;

layout(location = 0, index = 0) out vec4 fragColor;

void main() {
	// Sample the texture
	vec4 texColor = texture(celestialTexture, texCoord);
	
	// Apply celestial color tint and opacity
	fragColor = vec4(texColor.rgb * celestialColor, texColor.a * celestialOpacity);
	
	// Discard fully transparent pixels
	if (fragColor.a < 0.01) {
		discard;
	}
}