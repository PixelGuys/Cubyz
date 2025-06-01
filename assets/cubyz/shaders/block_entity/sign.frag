#version 460

layout(location = 0) in vec3 mvVertexPos;
layout(location = 1) in vec3 direction;
layout(location = 2) in vec3 light;
layout(location = 3) in vec2 uv;
layout(location = 4) flat in vec3 normal;

layout(location = 0) out vec4 fragColor;

layout(binding = 0) uniform sampler2D textureSampler;

layout(location = 9) uniform float contrast;

float lightVariation(vec3 normal) {
	const vec3 directionalPart = vec3(0, contrast/2, contrast);
	const float baseLighting = 1 - contrast;
	return baseLighting + dot(normal, directionalPart);
}

void main() {
	float normalVariation = lightVariation(normal);

	vec3 pixelLight = light*normalVariation;
	fragColor = texture(textureSampler, uv)*vec4(pixelLight, 1);
}
