#version 460

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
layout(location = 8) uniform mat4 lightProjectionMatrix;
layout(location = 9) uniform mat4 lightViewMatrix;
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
	vec3 dx = dFdx(shadowPos);
	vec3 dy = dFdy(shadowPos);

	vec2 duv_dx = dFdx(uv);
	vec2 duv_dy = dFdy(uv);

	vec2 texSize = vec2(16.0);
	vec2 texelFrac = fract(uv * texSize);
	vec2 texelOffset = (0.5 - texelFrac) / texSize;

	mat2 uvGrad = mat2(duv_dx, duv_dy);

	mat2 invUvGrad = inverse(uvGrad);

	vec2 screenOffset = invUvGrad * texelOffset;

	vec3 offset =
		dx * screenOffset.x +
		dy * screenOffset.y;

	vec3 snappedShadowPos = shadowPos + offset;

	vec4 lightPos =
		lightProjectionMatrix *
		lightViewMatrix *
		vec4(snappedShadowPos, 1.0);
	vec3 projCoords = lightPos.xyz;
	projCoords = projCoords * 0.5 + 0.5;
	float closestDepth = texture(shadowMap, projCoords.xy).r;
	float currentDepth = projCoords.z;
	currentDepth += 0.00018;
	float shadow = currentDepth > closestDepth ? 1.0 : 0.0;
	if(projCoords.z > 1.0)
        shadow = 0.0;
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
