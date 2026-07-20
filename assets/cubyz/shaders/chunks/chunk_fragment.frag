#version 460

#include "frame_uniforms.glsl"

layout(location = 0) in vec3 mvVertexPos;
layout(location = 1) in vec3 direction;
layout(location = 2) in vec3 sunLight;
layout(location = 3) in vec3 blockLight;
layout(location = 4) in vec2 uv;
layout(location = 5) in vec3 shadowPos;
layout(location = 6) flat in vec3 normal;
layout(location = 7) flat in int textureIndex;
layout(location = 8) flat in int isBackFace;
layout(location = 9) flat in float distanceForLodCheck;
layout(location = 10) flat in int opaqueInLod;
layout(location = 11) flat in mat4 worldToQuad;
layout(location = 15) flat in mat3 uvTransform;

layout(location = 0) out vec4 fragColor;

layout(binding = 0) uniform sampler2DArray textureSampler;
layout(binding = 1) uniform sampler2DArray emissionSampler;
layout(binding = 2) uniform sampler2DArray reflectivityAndAbsorptionSampler;
layout(binding = 4) uniform samplerCube reflectionMap;
layout(binding = 5) uniform sampler2D ditherTexture;
layout(binding = 6) uniform sampler2D shadowMap;

layout(location = 5) uniform float reflectionMapSize;
layout(location = 6) uniform float contrast;
layout(location = 7) uniform float lodDistance;
layout(location = 42) uniform vec3 lightDir;

layout(std430, binding = 1) buffer _animatedTexture
{
	float animatedTexture[];
};

vec3 square(vec3 x) {
	return x*x;
}

float lightVariation(vec3 normal) {
	const vec3 directionalPart = vec3(0, contrast/2, contrast);
	const float baseLighting = 1 - contrast;
	return baseLighting + dot(normal, directionalPart);
}

bool passDitherTest(float alpha) {
	if(opaqueInLod != 0) {
		if(distanceForLodCheck > lodDistance) return true;
		float factor = max(0, distanceForLodCheck - (lodDistance - 32.0))/32.0;
		alpha = alpha*(1 - factor) + factor;
	}
	return alpha > texture(ditherTexture, uv).r*255.0/256.0 + 0.5/256.0;
}

vec4 fixedCubeMapLookup(vec3 v) { // Taken from http://the-witness.net/news/2012/02/seamless-cube-map-filtering/
	float M = max(max(abs(v.x), abs(v.y)), abs(v.z));
	float scale = (reflectionMapSize - 1)/reflectionMapSize;
	if (abs(v.x) != M) v.x *= scale;
	if (abs(v.y) != M) v.y *= scale;
	if (abs(v.z) != M) v.z *= scale;
	return texture(reflectionMap, v);
}

float shadowCalculation() {
	if (dot(lightDir, normal) > 0.0) return 1.0;

	vec3 shadowPosUV = uvTransform * (worldToQuad * lightViewMatrix * vec4(shadowPos, 1.0)).xyz;
	shadowPosUV.xy = ceil(shadowPosUV.xy * 16.0) / 16.0;
	vec4 shadowPosSnapped = inverse(worldToQuad) * vec4(inverse(uvTransform) * shadowPosUV, 1.0);

	vec4 lightPos = lightProjectionMatrix * shadowPosSnapped;
	vec3 projCoords = lightPos.xyz;
	projCoords = projCoords * 0.5 + 0.5;
	if(projCoords.x >= 1.0 || projCoords.x <= 0.0 || projCoords.y >= 1.0 || projCoords.y <= 0.0 || projCoords.z >= 1.0 || projCoords.z <= 0.0) {
		return 0.0;
	}
	float closestDepth = texture(shadowMap, projCoords.xy).r;
	float currentDepth = projCoords.z;
	currentDepth += 0.0001;
	float shadow = currentDepth > closestDepth ? 1.0 : 0.0;
	return shadow;
}

void main() {
	float animatedTextureIndex = animatedTexture[textureIndex];
	float normalVariation = lightVariation(normal);
	vec3 textureCoords = vec3(uv, animatedTextureIndex);

	float reflectivity = texture(reflectivityAndAbsorptionSampler, textureCoords).a;
	float fresnelReflection = (1 + dot(normalize(direction), normal));
	fresnelReflection *= fresnelReflection;
	fresnelReflection *= min(1, 2*reflectivity); // Limit it to 2*reflectivity to avoid making every block reflective.
	reflectivity = reflectivity*fixedCubeMapLookup(reflect(direction, normal)).x;
	reflectivity = reflectivity*(1 - fresnelReflection) + fresnelReflection;

	vec3 shadowColor = vec3(0.5, 0.5, 0.35);

	float shadow = shadowCalculation();
	vec3 light = min(sqrt(square((1.0 - shadow*shadowColor)*sunLight) + square(blockLight)), vec3(31))/31;

	vec3 pixelLight = max(light*normalVariation, texture(emissionSampler, textureCoords).r*4);
	fragColor = texture(textureSampler, textureCoords)*vec4(pixelLight, 1);
	fragColor.rgb += reflectivity*pixelLight;

	if(!passDitherTest(fragColor.a)) discard;
	fragColor.a = 1;
}
