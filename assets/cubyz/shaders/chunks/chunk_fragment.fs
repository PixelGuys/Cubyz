#version 430

in vec3 mvVertexPos;
flat in int blockType;
flat in int faceNormal;
flat in int modelIndex;
flat in int isBackFace;
flat in int ditherSeed;
// For raymarching:
in vec3 startPosition;
in vec3 direction;

uniform int time;
uniform vec3 ambientLight;
uniform sampler2DArray texture_sampler;
uniform sampler2DArray emissionSampler;

layout(location = 0) out vec4 fragColor;

struct AnimationData {
	int frames;
	int time;
};

#define modelSize 16
struct VoxelModel {
	ivec4 minimum;
	ivec4 maximum;
	uint bitPackedData[modelSize*modelSize*modelSize/8];
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
layout(std430, binding = 4) buffer _voxelModels
{
	VoxelModel voxelModels[];
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

int getVoxel(int voxelIndex) {
	voxelIndex = (voxelIndex & 0xf) | (voxelIndex>>1 & 0xf0) | (voxelIndex>>2 & 0xf00);
	int shift = 4*(voxelIndex & 7);
	int arrayIndex = voxelIndex >> 3;
	return (int(voxelModels[modelIndex].bitPackedData[arrayIndex])>>shift & 15) - 6;
}

struct RayMarchResult {
	bool hitAThing;
	int normal;
	int textureDir;
	ivec3 voxelPosition;
};

RayMarchResult rayMarching(vec3 startPosition, vec3 direction) { // TODO: Mipmapped voxel models. (or maybe just remove them when they are far enough away?)
	// Branchless implementation of "A Fast Voxel Traversal Algorithm for Ray Tracing"  http://www.cse.yorku.ca/~amana/research/grid.pdf
	vec3 step = sign(direction);
	vec3 stepInIndex = step*vec3(1 << 10, 1 << 5, 1);
	int overflowMask = 1<<14 | 1<<9 | 1<<4;
	vec3 t1 = (floor(startPosition) - startPosition)/direction;
	vec3 tDelta = 1/direction;
	vec3 t2 = t1 + tDelta;
	tDelta = abs(tDelta);
	vec3 invTDelta = intBitsToFloat(floatBitsToInt(1.0) | modelSize)/tDelta;
	vec3 tMax = max(t1, t2) - tDelta;
	if(direction.x == 0) tMax.x = 1.0/0.0;
	if(direction.y == 0) tMax.y = 1.0/0.0;
	if(direction.z == 0) tMax.z = 1.0/0.0;
	
	ivec3 voxelPos = ivec3(floor(startPosition));
	int voxelIndex = voxelPos.x<<10 | voxelPos.y<<5 | voxelPos.z; // Stores the position as 0b0xxxx0yyyy0zzzz

	int lastNormal = faceNormal;
	int block = getVoxel(voxelIndex);
	float total_tMax = 0;
	
	int size = 16;
	ivec3 sizeMask = ivec3(size - 1);
	int it = 0;
	while(block > 0 && it < 48) {
		it++;
		vec3 tNext = tMax + block*tDelta;
		total_tMax = min(tNext.x, min(tNext.y, tNext.z));
		vec3 missingSteps = floor((total_tMax - tMax)*invTDelta);
		voxelIndex += int(dot(missingSteps, stepInIndex));
		tMax += missingSteps*tDelta;
		if((voxelIndex & overflowMask) != 0)
			return RayMarchResult(false, 0, 0, ivec3(0, 0, 0));
		block = getVoxel(voxelIndex);
	}
	if(total_tMax != 0) {
		if(tMax.x > tMax.y) {
			if(tMax.x > tMax.z) {
				lastNormal = 2 + (1 + int(step.x))/2;
			} else {
				lastNormal = 4 + (1 + int(step.z))/2;
			}
		} else {
			if(tMax.y > tMax.z) {
				lastNormal = 0 + (1 + int(step.y))/2;
			} else {
				lastNormal = 4 + (1 + int(step.z))/2;
			}
		}
	}
	voxelPos.x = voxelIndex>>10 & 15;
	voxelPos.y = voxelIndex>>5 & 15;
	voxelPos.z = voxelIndex & 15;
	int textureDir = -block;
	if(textureDir == 6) textureDir = lastNormal;
	return RayMarchResult(true, lastNormal, textureDir, voxelPos);
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

uint random3to1u(ivec3 v) {
	v &= 15;
	ivec4 fac = ivec4(11248723, 105436839, 45399083, 5412951);
	int seed = v.x*fac.x ^ v.y*fac.y ^ v.z*fac.z;
	return uint(seed)*uint(fac.w);
}

bool passDitherTest(float alpha) {
	ivec2 screenPos = ivec2(gl_FragCoord.xy);
	screenPos += random1to2(ditherSeed);
	screenPos &= 3;
	return alpha > ditherThresholds[screenPos.x*4 + screenPos.y];
}

void main() {
	RayMarchResult result;
	float variance = perpendicularFwidth(direction);
	if(variance <= 4.0) {
		result = rayMarching(startPosition, direction);
	} else {
		result = RayMarchResult(true, faceNormal, faceNormal, ivec3(startPosition)); // At some point it doesn't make sense to even draw the model.
	}
	if(!result.hitAThing) discard;
	int textureIndex = textureData[blockType].textureIndices[result.textureDir];
	textureIndex = textureIndex + time / animation[textureIndex].time % animation[textureIndex].frames;
	float normalVariation = normalVariations[result.normal];
	float lod = getLod(result.voxelPosition, result.normal, direction, variance);
	ivec2 textureCoords = getTextureCoords(result.voxelPosition, result.textureDir);
	fragColor = mipMapSample(texture_sampler, textureCoords, textureIndex, lod)*vec4(ambientLight*normalVariation, 1);

	if(!passDitherTest(fragColor.a)) discard;
	fragColor.a = 1;

	fragColor.rgb += mipMapSample(emissionSampler, textureCoords, textureIndex, lod).rgb;
	// TODO: Update the depth.
}
