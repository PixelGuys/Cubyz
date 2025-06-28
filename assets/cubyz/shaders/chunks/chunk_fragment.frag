#version 460

layout(location = 0) in vec3 mvVertexPos;
layout(location = 1) in vec3 direction;
layout(location = 2) in vec3 light;
layout(location = 3) in vec2 uv;
layout(location = 4) flat in vec3 normal;
layout(location = 5) flat in int textureIndex;
layout(location = 6) flat in int isBackFace;
layout(location = 7) flat in float distanceForLodCheck;
layout(location = 8) flat in int opaqueInLod;

layout(location = 0) out vec4 fragColor;

layout(binding = 0) uniform sampler2DArray textureSampler;
layout(binding = 1) uniform sampler2DArray emissionSampler;
layout(binding = 2) uniform sampler2DArray reflectivityAndAbsorptionSampler;
layout(binding = 4) uniform samplerCube reflectionMap;
layout(binding = 5) uniform sampler2D ditherTexture;

layout(location = 5) uniform float reflectionMapSize;
layout(location = 6) uniform float contrast;
layout(location = 7) uniform float lodDistance;

layout(std430, binding = 1) buffer _animatedTexture
{
	float animatedTexture[];
};

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

	vec3 pixelLight = max(light*normalVariation, texture(emissionSampler, textureCoords).r*4);
	fragColor = texture(textureSampler, textureCoords)*vec4(pixelLight, 1);
	fragColor.rgb += reflectivity*pixelLight;

	if(!passDitherTest(fragColor.a)) discard;
	fragColor.a = 1;
}
