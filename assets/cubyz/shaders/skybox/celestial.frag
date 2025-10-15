#version 460

layout (location = 0) in vec2 texCoord;
layout (location = 1) in float fragDistance; // Distance from camera

layout (location = 1) uniform float celestialOpacity;
layout (location = 2) uniform vec3 celestialColor;

struct Fog {
	vec3 color;
	float density;
};
layout (location = 3) uniform Fog fog;

layout(binding = 0) uniform sampler2D celestialTexture;

layout(location = 0, index = 0) out vec4 fragColor;

void main() {
	// Sample the texture
	vec4 texColor = texture(celestialTexture, texCoord);

	// Apply celestial color tint and opacity
	vec3 finalColor = texColor.rgb * celestialColor;
	
	// Apply fog
	float fogAmount = 1.0 - exp(-fog.density * fragDistance);
	finalColor = mix(finalColor, fog.color, fogAmount);
	
	fragColor = vec4(finalColor, texColor.a * celestialOpacity);

	// Discard fully transparent pixels
	if (fragColor.a < 0.01) {
		discard;
	}
}
