#version 460

layout(location = 0) in vec3 mvVertexPos;
layout(location = 1) in vec3 direction;
layout(location = 2) in vec2 uv;
layout(location = 3) flat in vec3 normal;
layout(location = 4) flat in uint textureIndexOffset;
layout(location = 5) flat in int isBackFace;
layout(location = 6) flat in float distanceForLodCheck;
layout(location = 7) flat in int opaqueInLod;
layout(location = 8) flat in uint lightBufferIndex;
layout(location = 9) flat in uvec2 lightArea;
layout(location = 10) in vec2 lightPosition;

layout(binding = 0) uniform sampler2DArray textureSampler;
layout(binding = 1) uniform sampler2DArray emissionSampler;
layout(binding = 2) uniform sampler2DArray reflectivityAndAbsorptionSampler;
layout(binding = 4) uniform samplerCube reflectionMap;
layout(binding = 5) uniform sampler2D ditherTexture;

layout(location = 5) uniform float reflectionMapSize;
layout(location = 6) uniform float contrast;
layout(location = 7) uniform float lodDistance;
layout(location = 0) uniform vec3 ambientLight;

layout(std430, binding = 1) buffer _animatedTexture
{
	float animatedTexture[];
};

layout(std430, binding = 13) buffer _textureData
{
	uint textureData[];
};

float ditherThresholds[16] = float[16] (
	1/17.0, 9/17.0, 3/17.0, 11/17.0,
	13/17.0, 5/17.0, 15/17.0, 7/17.0,
	4/17.0, 12/17.0, 2/17.0, 10/17.0,
	16/17.0, 8/17.0, 14/17.0, 6/17.0
);

bool passDitherTest(float alpha) {
	if(opaqueInLod != 0) {
		if(distanceForLodCheck > lodDistance) return true;
		float factor = max(0, distanceForLodCheck - (lodDistance - 32.0))/32.0;
		alpha = alpha*(1 - factor) + factor;
	}
	return alpha > texture(ditherTexture, uv).r*255.0/256.0 + 0.5/256.0;
}

uint readTextureIndex() {
	uint x = clamp(uint(lightPosition.x), 0, lightArea.x - 2);
	uint y = clamp(uint(lightPosition.y), 0, lightArea.y - 2);
	uint index = textureIndexOffset + x*(lightArea.y - 1) + y;
	return textureData[index >> 1] >> 16*(index & 1u) & 65535u;
}

void main() {
	uint textureIndex = readTextureIndex();
	float animatedTextureIndex = animatedTexture[textureIndex];
	vec3 textureCoords = vec3(uv, animatedTextureIndex);
	float alpha = texture(textureSampler, textureCoords).a;
	if(!passDitherTest(alpha)) discard;
}
