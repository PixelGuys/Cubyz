#version 430

in vec3 mvVertexPos;
flat in int blockType;
flat in int faceNormal;
flat in int modelIndex;
flat in int isBackFace;
in vec3 startPosition;
in vec3 direction;

uniform int time;
uniform vec3 ambientLight;
uniform sampler2DArray texture_sampler;
uniform sampler2DArray emissionSampler;

layout(binding = 3) uniform sampler2D depthTexture;

layout (location = 0, index = 0) out vec4 fragColor;
layout (location = 0, index = 1) out vec4 blendColor;

struct Fog {
	vec3 color;
	float density;
};

struct AnimationData {
	int frames;
	int time;
};

struct TextureData {
	int textureIndices[6];
	uint absorption;
	float reflectivity;
	float fogDensity;
	uint fogColor;
};

layout(std430, binding = 0) buffer _animation
{
	AnimationData animation[];
};
layout(std430, binding = 1) buffer _textureData
{
	TextureData textureData[];
};


const float[6] normalVariations = float[6](
	1.0, //vec3(0, 1, 0),
	0.84, //vec3(0, -1, 0),
	0.92, //vec3(1, 0, 0),
	0.92, //vec3(-1, 0, 0),
	0.96, //vec3(0, 0, 1),
	0.88 //vec3(0, 0, -1)
);
const vec3[6] normals = vec3[6](
	vec3(0, 1, 0),
	vec3(0, -1, 0),
	vec3(1, 0, 0),
	vec3(-1, 0, 0),
	vec3(0, 0, 1),
	vec3(0, 0, -1)
);

uniform float nearPlane;

uniform Fog fog;

ivec3 random3to3(ivec3 v) {
	v &= 15;
	ivec3 fac = ivec3(11248723, 105436839, 45399083);
	int seed = v.x*fac.x ^ v.y*fac.y ^ v.z*fac.z;
	v = seed*fac;
	return v;
}

float snoise(vec3 v){ // TODO: Maybe use a cubemap.
	const vec2 C = vec2(1.0/6.0, 1.0/3.0);

	// First corner
	vec3 i = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);

	// Other corners
	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);

	// x0 = x0 - 0. + 0.0 * C 
	vec3 x1 = x0 - i1 + 1.0*C.xxx;
	vec3 x2 = x0 - i2 + 2.0*C.xxx;
	vec3 x3 = x0 - 1. + 3.0*C.xxx;

	// Get gradients:
	ivec3 rand = random3to3(ivec3(i));
	vec3 p0 = vec3(rand);
	
	rand = random3to3((ivec3(i + i1)));
	vec3 p1 = vec3(rand);
	
	rand = random3to3((ivec3(i + i2)));
	vec3 p2 = vec3(rand);
	
	rand = random3to3((ivec3(i + 1)));
	vec3 p3 = vec3(rand);

	// Mix final noise value
	vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
	m = m*m;
	return 42.0*dot(m*m, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)))/(1 << 31);
}

vec3 unpackColor(uint color) {
	return vec3(
		color>>16 & 255u,
		color>>8 & 255u,
		color & 255u
	)/255.0;
}

float calculateFogDistance(float depthBufferValue, float fogDensity) {
	float distCameraTerrain = nearPlane*fogDensity/depthBufferValue;
	float distFromCamera = abs(mvVertexPos.z)*fogDensity;
	float distFromTerrain = distFromCamera - distCameraTerrain;
	if(distCameraTerrain < 10) { // Resolution range is sufficient.
		return distFromTerrain;
	} else {
		// Here we have a few options to deal with this. We could for example weaken the fog effect to fit the entire range.
		// I decided to keep the fog strength close to the camera and far away, with a fog-free region in between.
		// I decided to this because I want far away fog to work (e.g. a distant ocean) as well as close fog(e.g. the top surface of the water when the player is under it)
		if(distFromTerrain > -5 && depthBufferValue != 0) {
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
	float oldAlpha = fragColor.a;
	fragColor.a *= 1.0/fogFactor;
	fragColor.rgb += fragColor.a*fogColor;
	fragColor.rgb -= oldAlpha*fogColor;
}

void applyBackfaceFog(float fogDistance, vec3 fogColor) {
	float fogFactor = exp(fogDistance);
	float oldAlpha = fragColor.a;
	fragColor.a *= fogFactor;
	fragColor.rgb -= oldAlpha*fogColor;
	fragColor.rgb += fragColor.a*fogColor;
}

vec2 getTextureCoordsNormal(vec3 voxelPosition, int textureDir) {
	switch(textureDir) {
		case 0:
			return vec2(15 - voxelPosition.x, voxelPosition.z);
		case 1:
			return vec2(voxelPosition.x, voxelPosition.z);
		case 2:
			return vec2(15 - voxelPosition.z, voxelPosition.y);
		case 3:
			return vec2(voxelPosition.z, voxelPosition.y);
		case 4:
			return vec2(voxelPosition.x, voxelPosition.y);
		case 5:
			return vec2(15 - voxelPosition.x, voxelPosition.y);
	}
}

void main() {
	int textureIndex = textureData[blockType].textureIndices[faceNormal];
	textureIndex = textureIndex + time / animation[textureIndex].time % animation[textureIndex].frames;
	float normalVariation = normalVariations[faceNormal];
	float fogDistance = calculateFogDistance(texelFetch(depthTexture, ivec2(gl_FragCoord.xy), 0).r, textureData[blockType].fogDensity);
	float airFogDistance = calculateFogDistance(texelFetch(depthTexture, ivec2(gl_FragCoord.xy), 0).r, fog.density);
	vec3 fogColor = unpackColor(textureData[blockType].fogColor);
	fragColor = vec4(0, 0, 0, 1);
	if(isBackFace == 0) {

		vec4 textureColor = texture(texture_sampler, vec3(getTextureCoordsNormal(startPosition/16, faceNormal), textureIndex))*vec4(ambientLight*normalVariation, 1);

		if (textureColor.a == 1) discard;

		textureColor.rgb *= textureColor.a;
		blendColor.rgb = unpackColor(textureData[blockType].absorption);

		// Fake reflection:
		// TODO: Also allow this for opaque pixels.
		// TODO: Change this when it rains.
		// TODO: Normal mapping.
		// TODO: Allow textures to contribute to this term.
		textureColor.rgb += (textureData[blockType].reflectivity/2*vec3(snoise(normalize(reflect(direction, normals[faceNormal])))) + vec3(textureData[blockType].reflectivity))*ambientLight*normalVariation;
		textureColor.rgb += texture(emissionSampler, vec3(getTextureCoordsNormal(startPosition/16, faceNormal), textureIndex)).rgb;
		blendColor.rgb *= 1 - textureColor.a;
		textureColor.a = 1;

		if(textureData[blockType].fogDensity == 0.0) {
			// Apply the air fog, compensating for the missing back-face:
			applyFrontfaceFog(airFogDistance, fog.color);
		} else {
			// Apply the block fog:
			applyFrontfaceFog(fogDistance, fogColor);
		}

		// Apply the texture+absorption
		fragColor.rgb *= blendColor.rgb;
		fragColor.rgb += textureColor.rgb*fragColor.a;

		// Apply the air fog:
		applyBackfaceFog(airFogDistance, fog.color);
	} else {
		// Apply the air fog:
		applyFrontfaceFog(airFogDistance, fog.color);

		// Apply the texture:
		vec4 textureColor = texture(texture_sampler, vec3(getTextureCoordsNormal(startPosition/16, faceNormal), textureIndex))*vec4(ambientLight*normalVariation, 1);
		blendColor.rgb = vec3(1 - textureColor.a);
		fragColor.rgb *= blendColor.rgb;
		fragColor.rgb += textureColor.rgb*textureColor.a*fragColor.a;

		// Apply the block fog:
		applyBackfaceFog(fogDistance, fogColor);
	}
}
