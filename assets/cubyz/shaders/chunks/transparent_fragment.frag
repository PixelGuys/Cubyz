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

layout(location = 0, index = 0) out vec4 fragColor;
layout(location = 0, index = 1) out vec4 blendColor;

layout(binding = 0) uniform sampler2DArray textureSampler;
layout(binding = 1) uniform sampler2DArray emissionSampler;
layout(binding = 2) uniform sampler2DArray reflectivityAndAbsorptionSampler;
layout(binding = 4) uniform samplerCube reflectionMap;
layout(binding = 5) uniform sampler2D depthTexture;

layout(location = 3) uniform ivec3 playerPositionInteger;
layout(location = 4) uniform vec3 playerPositionFraction;

layout(location = 5) uniform float reflectionMapSize;
layout(location = 6) uniform float contrast;
layout(location = 0) uniform vec3 ambientLight;

layout(location = 8) uniform float zNear;
layout(location = 9) uniform float zFar;

struct Fog {
	vec3 color;
	float density;
	float fogLower;
	float fogHigher;
};

layout(location = 10) uniform Fog fog;

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

layout(std430, binding = 10) buffer _lightData
{
	uint lightData[];
};

layout(std430, binding = 13) buffer _textureData
{
	uint textureData[];
};

float lightVariation(vec3 normal) {
	const vec3 directionalPart = vec3(0, contrast/2, contrast);
	const float baseLighting = 1 - contrast;
	return baseLighting + dot(normal, directionalPart);
}

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

float densityIntegral(float dist, float zStart, float zDist, float fogLower, float fogHigher) {
	// The density is constant until fogLower, then gets smaller linearly until reaching fogHigher, past which there is no fog.
	if(zDist < 0) {
		zStart += zDist;
		zDist = -zDist;
	}
	if(abs(zDist) < 0.001) {
		zDist = 0.001;
	}
	float beginLower = min(fogLower, zStart);
	float endLower = min(fogLower, zStart + zDist);
	float beginMid = max(fogLower, min(fogHigher, zStart));
	float endMid = max(fogLower, min(fogHigher, zStart + zDist));
	float midIntegral = -0.5*(endMid - fogHigher)*(endMid - fogHigher)/(fogHigher - fogLower) - -0.5*(beginMid - fogHigher)*(beginMid - fogHigher)/(fogHigher - fogLower);
	if(fogHigher == fogLower) midIntegral = 0;

	return (endLower - beginLower + midIntegral)/zDist*dist;
}

float calculateFogDistance(float dist, float densityAdjustment, float zStart, float zScale, float fogDensity, float fogLower, float fogHigher) {
	float distCameraTerrain = densityIntegral(dist*densityAdjustment, zStart, zScale*dist*densityAdjustment, fogLower, fogHigher)*fogDensity;
	float distFromCamera = abs(densityIntegral(mvVertexPos.y*densityAdjustment, zStart, zScale*mvVertexPos.y*densityAdjustment, fogLower, fogHigher))*fogDensity;
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
vec3 unpack15BitLight(uint val) {
	return vec3(
		val >> 10 & 31u,
		val >> 5 & 31u,
		val & 31u
	);
}

vec3 square(vec3 x) {
	return x*x;
}

vec3 readLightValue() {
	uint x = clamp(uint(lightPosition.x), 0, lightArea.x - 1);
	uint y = clamp(uint(lightPosition.y), 0, lightArea.y - 1);
	uint light00 = lightData[lightBufferIndex + (x*lightArea.y + y)];
	uint light01 = lightData[lightBufferIndex + (x*lightArea.y + y + 1)];
	uint light10 = lightData[lightBufferIndex + ((x + 1)*lightArea.y + y)];
	uint light11 = lightData[lightBufferIndex + ((x + 1)*lightArea.y + y + 1)];
	float xFactor = lightPosition.x - x;
	float yFactor = lightPosition.y - y;
	vec3 sunLight = mix(
		mix(unpack15BitLight(light00 >> 15), unpack15BitLight(light01 >> 15), yFactor),
		mix(unpack15BitLight(light10 >> 15), unpack15BitLight(light11 >> 15), yFactor),
		xFactor
	);
	vec3 blockLight = mix(
		mix(unpack15BitLight(light00), unpack15BitLight(light01), yFactor),
		mix(unpack15BitLight(light10), unpack15BitLight(light11), yFactor),
		xFactor
	);
	return min(sqrt(square(sunLight*ambientLight) + square(blockLight)), vec3(31))/31;
}

uint readTextureIndex() {
	uint x = clamp(uint(lightPosition.x), 0, lightArea.x - 2);
	uint y = clamp(uint(lightPosition.y), 0, lightArea.y - 2);
	uint index = textureIndexOffset + x*(lightArea.y - 1) + y;
	return textureData[index >> 1] >> 16*(index & 1u) & 65535u;
}

void main() {
	vec3 light = readLightValue();
	uint textureIndex = readTextureIndex();
	float animatedTextureIndex = animatedTexture[textureIndex];
	vec3 textureCoords = vec3(uv, animatedTextureIndex);
	float normalVariation = lightVariation(normal);
	float densityAdjustment = sqrt(dot(mvVertexPos, mvVertexPos))/abs(mvVertexPos.y);
	float dist = zFromDepth(texelFetch(depthTexture, ivec2(gl_FragCoord.xy), 0).r);
	float fogDistance = calculateFogDistance(dist, densityAdjustment, playerPositionFraction.z, normalize(direction).z, fogData[int(animatedTextureIndex)].fogDensity, 1e10, 1e10);
	float airFogDistance = calculateFogDistance(dist, densityAdjustment, playerPositionFraction.z, normalize(direction).z, fog.density, fog.fogLower - playerPositionInteger.z, fog.fogHigher - playerPositionInteger.z);
	vec3 fogColor = unpackColor(fogData[int(animatedTextureIndex)].fogColor);
	vec3 pixelLight = max(light*normalVariation, texture(emissionSampler, textureCoords).r*4);
	vec4 textureColor = texture(textureSampler, textureCoords)*vec4(pixelLight, 1);

	float reflectivity = texture(reflectivityAndAbsorptionSampler, textureCoords).a;
	float fresnelReflection = (1 + dot(normalize(direction), normal));
	fresnelReflection *= fresnelReflection;
	fresnelReflection *= min(1, 2*reflectivity); // Limit it to 2*reflectivity to avoid making every block reflective.
	reflectivity = reflectivity*fixedCubeMapLookup(reflect(direction, normal)).x;
	reflectivity = reflectivity*(1 - fresnelReflection) + fresnelReflection;
	textureColor.rgb *= textureColor.a;
	textureColor.rgb += reflectivity*pixelLight;
	blendColor.rgb = vec3((1 - textureColor.a)*(1 - fresnelReflection));

	if(isBackFace == 0) {
		vec3 absorption = texture(reflectivityAndAbsorptionSampler, textureCoords).rgb;
		blendColor.rgb *= absorption;

		// Fake reflection:
		// TODO: Change this when it rains.
		// TODO: Normal mapping.
		textureColor.rgb += texture(emissionSampler, textureCoords).rgb;

		if(fogData[int(animatedTextureIndex)].fogDensity == 0.0) {
			// Apply the air fog, compensating for the potentially missing back-face:
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
		fragColor.rgb *= blendColor.rgb;
		fragColor.rgb += textureColor.rgb;

		// Apply the block fog:
		if(fogData[int(animatedTextureIndex)].fogDensity == 0.0) {
			// Apply the air fog, compensating for the above line where I compensated for the potentially missing back-face.
			applyBackfaceFog(airFogDistance, fog.color);
		} else {
			applyBackfaceFog(fogDistance, fogColor);
		}
	}
	blendColor.rgb *= fragColor.a;
	fragColor.a = 1;
}
