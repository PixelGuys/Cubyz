#version 430

layout(location = 0) out vec4 fragColor;

layout(location = 0) in vec3 textureCoords;
layout(location = 1) flat in vec3 light;

layout(binding = 0) uniform sampler2DArray textureSampler;
layout(binding = 1) uniform sampler2DArray emissionTextureSampler;
layout(binding = 2) uniform sampler2DArray blockTextureSampler;

void main() {
	vec4 texColor;
	vec3 pixelLight;

	// Negative textureIndex indicates block texture
	if (textureCoords.z < 0) {
		float blockTexIndex = -textureCoords.z - 1;
		texColor = texture(blockTextureSampler, vec3(textureCoords.xy, blockTexIndex));
		pixelLight = light; // blocks don't have emission
	} else {
		texColor = texture(textureSampler, textureCoords);
		pixelLight = max(light, texture(emissionTextureSampler, textureCoords).r*4);
	}

	if(texColor.a < 0.5) discard;
	fragColor = texColor*vec4(pixelLight, 1);
}
