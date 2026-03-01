#version 430

layout(location = 0) out vec4 fragColor;

layout(location = 0) in vec3 textureCoords;
layout(location = 1) flat in vec3 light;

layout(binding = 0) uniform sampler2DArray textureSampler;
layout(binding = 1) uniform sampler2DArray emissionTextureSampler;
layout(binding = 2) uniform sampler2DArray blockTextureSampler;

void main() {
	bool isBlock = textureCoords.z < 0.0;

	float layer = isBlock ? (-textureCoords.z - 1.0) : textureCoords.z;

	vec4 texColor = isBlock
		? texture(blockTextureSampler, vec3(textureCoords.xy, layer))
		: texture(textureSampler, vec3(textureCoords.xy, layer));

	if (texColor.a < 0.5)
		discard;

	float emission = texture(emissionTextureSampler, vec3(textureCoords.xy, layer)).r * 4.0;
	vec3 pixelLight = mix(max(light, vec3(emission)), light, float(isBlock));

	fragColor = texColor * vec4(pixelLight, 1.0);
}
