#version 430

in vec3 mvVertexPos;
in vec3 direction;
in vec3 light;
in vec2 uv;
flat in vec3 normal;
flat in int textureIndex;
flat in int isBackFace;
flat in int ditherSeed;

uniform sampler2DArray texture_sampler;
uniform sampler2DArray emissionSampler;
uniform sampler2DArray reflectivityAndAbsorptionSampler;
uniform samplerCube reflectionMap;
uniform float reflectionMapSize;
uniform float contrast;

layout(binding = 5) uniform sampler2D depthTexture;

layout (location = 0, index = 0) out vec4 fragColor;
layout (location = 0, index = 1) out vec4 blendColor;

struct Fog {
	vec3 color;
	float density;
};

layout(std430, binding = 1) buffer _animatedTexture
{
	float animatedTexture[];
};

struct FogData {
	float fogDensity;
	uint fogColor;
};

layout(std430, binding = 7) buffer _fogData
{
	FogData fogData[];
};

float lightVariation(vec3 normal) {
	const vec3 directionalPart = vec3(0, contrast/2, contrast);
	const float baseLighting = 1 - contrast;
	return baseLighting + dot(normal, directionalPart);
}

uniform float zNear;
uniform float zFar;

uniform Fog fog;

vec3 unpackColor(uint color) {
	return vec3(
		color>>16 & 255u,
		color>>8 & 255u,
		color & 255u
	)/255.0;
}

float zFromDepth(float depthBufferValue) {
	return zNear*zFar/(depthBufferValue*(zNear - zFar) + zFar);
}

float calculateFogDistance(float dist, float fogDensity) {
	float distCameraTerrain = dist*fogDensity;
	float distFromCamera = abs(mvVertexPos.y)*fogDensity;
	float distFromTerrain = distFromCamera - distCameraTerrain;
	if(distCameraTerrain < 10) { // Resolution range is sufficient.
		return distFromTerrain;
	} else {
		// Here we have a few options to deal with this. We could for example weaken the fog effect to fit the entire range.
		// I decided to keep the fog strength close to the camera and far away, with a fog-free region in between.
		// I decided to this because I want far away fog to work (e.g. a distant ocean) as well as close fog(e.g. the top surface of the water when the player is under it)
		if(distFromTerrain > -5) {
			return distFromTerrain;
		} else if(distFromCamera < 5) {
			return distFromCamera - 10;
		} else {
			return -5;
		}
	}
}

void applyFrontfaceFog(float fogDistance, vec3 fogColor) {
	float fogFactor = exp(fogDistance);
	fragColor.rgb = fogColor*(1 - fogFactor);
	fragColor.a = fogFactor;
}

void applyBackfaceFog(float fogDistance, vec3 fogColor) {
	float fogFactor = exp(-fogDistance);
	fragColor.rgb = fragColor.rgb*fogFactor + fogColor*(1 - fogFactor);
	fragColor.a *= fogFactor;
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
	vec3 textureCoords = vec3(uv, animatedTextureIndex);
	float normalVariation = lightVariation(normal);
	float densityAdjustment = sqrt(dot(mvVertexPos, mvVertexPos))/abs(mvVertexPos.y);
	float dist = zFromDepth(texelFetch(depthTexture, ivec2(gl_FragCoord.xy), 0).r);
	float fogDistance = calculateFogDistance(dist, fogData[int(animatedTextureIndex)].fogDensity*densityAdjustment);
	float airFogDistance = calculateFogDistance(dist, fog.density*densityAdjustment);
	vec3 fogColor = unpackColor(fogData[int(animatedTextureIndex)].fogColor);
	vec3 pixelLight = max(light*normalVariation, texture(emissionSampler, textureCoords).r*4);
	vec4 textureColor = texture(texture_sampler, textureCoords)*vec4(pixelLight, 1);
	float reflectivity = texture(reflectivityAndAbsorptionSampler, textureCoords).a;
	vec3 absorption = texture(reflectivityAndAbsorptionSampler, textureCoords).rgb;
	if(isBackFace == 0) {
		textureColor.rgb *= textureColor.a;
		blendColor.rgb = absorption;

		// Fake reflection:
		// TODO: Change this when it rains.
		// TODO: Normal mapping.
		textureColor.rgb += (reflectivity*fixedCubeMapLookup(reflect(direction, normal)).xyz)*pixelLight;
		textureColor.rgb += texture(emissionSampler, textureCoords).rgb;
		blendColor.rgb *= 1 - textureColor.a;
		textureColor.a = 1;

		if(fogData[int(animatedTextureIndex)].fogDensity == 0.0) {
			// Apply the air fog, compensating for the missing back-face:
			applyFrontfaceFog(airFogDistance, fog.color);
		} else {
			// Apply the block fog:
			applyFrontfaceFog(fogDistance, fogColor);
		}

		// Apply the texture+absorption
		fragColor.rgb *= blendColor.rgb;
		fragColor.rgb += textureColor.rgb;

		// Apply the air fog:
		applyBackfaceFog(airFogDistance, fog.color);
	} else {
		// Apply the air fog:
		applyFrontfaceFog(airFogDistance, fog.color);

		// Apply the texture:
		blendColor.rgb = vec3(1 - textureColor.a);
		fragColor.rgb *= blendColor.rgb;
		fragColor.rgb += textureColor.rgb*textureColor.a;

		// Apply the block fog:
		applyBackfaceFog(fogDistance, fogColor);
	}
	blendColor.rgb *= fragColor.a;
	fragColor.a = 1;
}
