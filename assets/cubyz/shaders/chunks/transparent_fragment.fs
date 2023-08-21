#version 430

in vec3 mvVertexPos;
flat in int blockType;
flat in int faceNormal;
flat in int modelIndex;
in vec3 startPosition;
in vec3 direction;

uniform int time;
uniform vec3 ambientLight;
uniform sampler2DArray texture_sampler;
uniform sampler2DArray emissionSampler;

layout (location = 0, index = 0) out vec4 fragColor;
layout (location = 0, index = 1) out vec4 blendColor;

struct Fog {
	bool activ;
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


uniform Fog fog;
uniform Fog waterFog; // TODO: Select fog from texture

vec4 calcFog(vec3 pos, vec4 color, Fog fog) {
	float distance = length(pos);
	float fogFactor = 1.0/exp((distance*fog.density)*(distance*fog.density));
	fogFactor = clamp(fogFactor, 0.0, 1.0);
	vec4 resultColor = mix(vec4(fog.color, 0), color, fogFactor);
	return resultColor;
}

ivec2 getTextureCoords(ivec3 voxelPosition, int textureDir) {
	switch(textureDir) {
		case 0:
			return ivec2(15 - voxelPosition.x, voxelPosition.z);
		case 1:
			return ivec2(voxelPosition.x, voxelPosition.z);
		case 2:
			return ivec2(15 - voxelPosition.z, voxelPosition.y);
		case 3:
			return ivec2(voxelPosition.z, voxelPosition.y);
		case 4:
			return ivec2(voxelPosition.x, voxelPosition.y);
		case 5:
			return ivec2(15 - voxelPosition.x, voxelPosition.y);
	}
}

float getLod(ivec3 voxelPosition, int normal, vec3 direction, float variance) {
	return max(0, min(4, log2(variance*length(direction)/abs(dot(vec3(normals[normal]), direction)))));
}

float perpendicularFwidth(vec3 direction) { // Estimates how big fwidth would be if the fragment normal was perpendicular to the light direction.
	vec3 variance = dFdx(direction);
	variance += direction;
	variance = variance*length(direction)/length(variance);
	variance -= direction;
	return 16*length(variance);
}

vec4 mipMapSample(sampler2DArray texture, ivec2 textureCoords, int textureIndex, float lod) { // TODO: anisotropic filtering?
	int lowerLod = int(floor(lod));
	int higherLod = lowerLod+1;
	float interpolation = lod - lowerLod;
	vec4 lower = texelFetch(texture, ivec3(textureCoords >> lowerLod, textureIndex), lowerLod);
	vec4 higher = texelFetch(texture, ivec3(textureCoords >> higherLod, textureIndex), higherLod);
	return higher*interpolation + (1 - interpolation)*lower;
}


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

void main() {
	float variance = perpendicularFwidth(direction);
	int textureIndex = textureData[blockType].textureIndices[faceNormal];
	textureIndex = textureIndex + time / animation[textureIndex].time % animation[textureIndex].frames;
	float normalVariation = normalVariations[faceNormal];
	float lod = getLod(ivec3(startPosition), faceNormal, direction, variance);
	ivec2 textureCoords = getTextureCoords(ivec3(startPosition), faceNormal);
	fragColor = mipMapSample(texture_sampler, textureCoords, textureIndex, lod)*vec4(ambientLight*normalVariation, 1);

	if (fragColor.a == 1) discard;

	if (fog.activ) {
		// TODO: Underwater fog if possible.
	}
	fragColor.rgb *= fragColor.a;
	blendColor.rgb = unpackColor(textureData[blockType].absorption);

	// Fake reflection:
	// TODO: Also allow this for opaque pixels.
	// TODO: Change this when it rains.
	// TODO: Normal mapping.
	// TODO: Allow textures to contribute to this term.
	fragColor.rgb += (textureData[blockType].reflectivity/2*vec3(snoise(normalize(reflect(direction, normals[faceNormal])))) + vec3(textureData[blockType].reflectivity))*ambientLight*normalVariation;
	fragColor.rgb += mipMapSample(emissionSampler, textureCoords, textureIndex, lod).rgb;
	blendColor.rgb *= 1 - fragColor.a;
	fragColor.a = 1;

	if (fog.activ) {
		fragColor = calcFog(mvVertexPos, fragColor, fog);
		blendColor.rgb *= fragColor.a;
		fragColor.a = 1;
	}
	// TODO: Update the depth.
}
