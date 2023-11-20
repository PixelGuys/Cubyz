#version 430

in vec3 mvVertexPos;
in vec3 light;
in vec3 chunkPos;
flat in int blockType;
flat in int faceNormal;
flat in int modelIndex;
flat in int isBackFace;
flat in int ditherSeed;
// For raymarching:
flat in ivec3 minPos;
flat in ivec3 maxPos;
in vec3 startPosition;
in vec3 direction;

uniform sampler2DArray texture_sampler;
uniform sampler2DArray emissionSampler;
uniform uint chunkDataIndex;
uniform vec3 ambientLight;
uniform int voxelSize;

layout(location = 0) out vec4 fragColor;

struct TextureData {
	uint textureIndices[6];
	uint absorption;
	float reflectivity;
	float fogDensity;
	uint fogColor;
};

layout(std430, binding = 1) buffer _textureData
{
	TextureData textureData[];
};

struct ChunkData {
	uint lightMapPtrs[6*6*6];
};

struct LightData {
	int values[8*8*8];
};

layout(std430, binding = 7) buffer _chunkData
{
	ChunkData chunkData[];
};
layout(std430, binding = 8) buffer _lightData
{
	LightData lightData[];
};

vec3 sampleLight(ivec3 pos) {
	pos += 8;
	ivec3 rough = pos/8;
	int roughIndex = (rough.x*6 + rough.y)*6 + rough.z;
	ivec3 fine = pos&7;
	int fineIndex = (fine.x*8 + fine.y)*8 + fine.z;
	int lightValue = lightData[chunkData[chunkDataIndex].lightMapPtrs[roughIndex]].values[fineIndex];
	vec3 sunLight = vec3(
		lightValue >> 25 & 31,
		lightValue >> 20 & 31,
		lightValue >> 15 & 31
	);
	vec3 blockLight = vec3(
		lightValue >> 10 & 31,
		lightValue >> 5 & 31,
		lightValue >> 0 & 31
	);
	return max(sunLight*ambientLight, blockLight)/32;
}

vec3 sCurve(vec3 x) {
	return (3*x - 2*x*x)*x;
}

vec3 getLight(vec3 pos, vec3 normal) {
	pos += normal/2;
	pos -= vec3(0.5, 0.5, 0.5);
	ivec3 start = ivec3(floor(pos));
	vec3 diff = sCurve(pos - start);
	vec3 invDiff = 1 - diff;

	vec3 state = vec3(0);
	for(int dx = 0; dx < 2; dx++) {
		for(int dy = 0; dy < 2; dy++) {
			for(int dz = 0; dz < 2; dz++) {
				ivec3 delta = ivec3(dx, dy, dz);
				vec3 light = sampleLight(start + delta);
				bvec3 isOne = bvec3(notEqual(delta, ivec3(0)));
				vec3 interpolation = mix(invDiff, diff, isOne);
				state += light*interpolation.x*interpolation.y*interpolation.z;
			}
		}
	}
	return state;
}


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

float ditherThresholds[16] = float[16] (
	1/17.0, 9/17.0, 3/17.0, 11/17.0,
	13/17.0, 5/17.0, 15/17.0, 7/17.0,
	4/17.0, 12/17.0, 2/17.0, 10/17.0,
	16/17.0, 8/17.0, 14/17.0, 6/17.0
);

ivec2 random1to2(int v) {
	ivec4 fac = ivec4(11248723, 105436839, 45399083, 5412951);
	int seed = v.x*fac.x ^ fac.y;
	return seed*fac.zw;
}

bool passDitherTest(float alpha) {
	ivec2 screenPos = ivec2(gl_FragCoord.xy);
	screenPos += random1to2(ditherSeed);
	screenPos &= 3;
	return alpha > ditherThresholds[screenPos.x*4 + screenPos.y];
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
	uint textureIndex = textureData[blockType].textureIndices[faceNormal];
	float normalVariation = normalVariations[faceNormal];
	vec3 textureCoords = vec3(getTextureCoordsNormal(startPosition/16, faceNormal), textureIndex);
	vec3 light = getLight(chunkPos + startPosition/16.0/voxelSize, normals[faceNormal]);
	fragColor = texture(texture_sampler, textureCoords)*vec4(light*normalVariation, 1);

	if(!passDitherTest(fragColor.a)) discard;
	fragColor.a = 1;

	fragColor.rgb += texture(emissionSampler, textureCoords).rgb;
}
