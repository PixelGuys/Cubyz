#version 430

in vec2 outTexCoord;
in vec3 mvVertexPos;
in vec3 outLight;
flat in vec3 normal;

out vec4 fragColor;

uniform sampler2D texture_sampler;
uniform float contrast;

float lightVariation(vec3 normal) {
	const vec3 directionalPart = vec3(0, contrast/2, contrast);
	const float baseLighting = 1 - contrast;
	return baseLighting + dot(normal, directionalPart);
}

void main() {
	fragColor = texture(texture_sampler, outTexCoord)*vec4(outLight*lightVariation(normal), 1);
}
