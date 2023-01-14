#version 430

in vec3 mvVertexPos;
flat in int blockType;
flat in int faceNormal;
flat in int modelIndex;
// For raymarching:
in vec3 startPosition;
in vec3 direction;
// For mipmapping:
flat in vec2 pixelSizeX; // Where one voxel unit is facing in screenspace.
flat in vec2 pixelSizeY; // Where one voxel unit is facing in screenspace.
flat in vec2 pixelSizeZ; // Where one voxel unit is facing in screenspace.

uniform int time;
uniform vec3 ambientLight;
uniform sampler2DArray texture_sampler;
uniform sampler2DArray emissionSampler;

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 position;

struct Fog {
	bool activ;
	vec3 color;
	float density;
};

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

layout(std430, binding = 0) buffer _animation
{
	AnimationData animation[];
};
layout(std430, binding = 1) buffer _textureIndices
{
	int textureIndices[][6];
};
layout(std430, binding = 4) buffer _voxelModels
{
	VoxelModel voxelModels[];
};


const float[6] normalVariations = float[6](
	1.0, //vec3(0, 1, 0),
	0.88, //vec3(0, -1, 0),
	0.92, //vec3(1, 0, 0),
	0.92, //vec3(-1, 0, 0),
	0.96, //vec3(0, 0, 1),
	0.88 //vec3(0, 0, -1)
);


uniform Fog fog;
uniform Fog waterFog; // TODO: Select fog from texture

vec4 calcFog(vec3 pos, vec4 color, Fog fog) {
	float distance = length(pos);
	float fogFactor = 1.0/exp((distance*fog.density)*(distance*fog.density));
	fogFactor = clamp(fogFactor, 0.0, 1.0);
	vec4 resultColor = mix(vec4(fog.color, 1), color, fogFactor);
	return resultColor;
}

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
	vec3 tDelta = 1/(direction);
	vec3 t2 = t1 + tDelta;
	tDelta = abs(tDelta);
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
		vec3 missingSteps = floor((total_tMax - tMax)/tDelta + 0.00001);
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

float getLod(ivec3 voxelPosition, int normal, vec3 startPosition) {
	vec2 one;
	vec2 other;
	switch(normal) {
		case 0:
		case 1:
			one = pixelSizeX;
			other = pixelSizeZ;
			break;
		case 2:
		case 3:
			one = pixelSizeY;
			other = pixelSizeZ;
			break;
		case 4:
		case 5:
			one = pixelSizeX;
			other = pixelSizeY;
			break;
	}
	float area = abs(one.x*other.y - one.y*other.x);
	float biggestSideLength = max(length(one), length(other));
	return max(0, min(4, -1 + log2(2.0*biggestSideLength/area)));
}

vec4 mipMapSample(sampler2DArray texture, ivec2 textureCoords, int textureIndex, float lod) { // TODO: anisotropic filtering?
	int lowerLod = int(floor(lod));
	int higherLod = lowerLod+1;
	float interpolation = lod - lowerLod;
	vec4 lower = texelFetch(texture, ivec3(textureCoords >> lowerLod, textureIndex), lowerLod);
	vec4 higher = texelFetch(texture, ivec3(textureCoords >> higherLod, textureIndex), higherLod);
	return higher*interpolation + (1 - interpolation)*lower;
}

void main() {
	RayMarchResult result;
	if(min(1.0/length(pixelSizeX), min(1.0/length(pixelSizeY), 1.0/length(pixelSizeZ))) <= 4.0) {
		result = rayMarching(startPosition, direction);
	} else {
		result = RayMarchResult(true, faceNormal, faceNormal, ivec3(startPosition)); // At some point it doesn't make sense to even draw the model.
	}
	if(!result.hitAThing) discard;
	int textureIndex = textureIndices[blockType][result.textureDir];
	textureIndex = textureIndex + time / animation[textureIndex].time % animation[textureIndex].frames;
	float normalVariation = normalVariations[result.normal];
	float lod = getLod(result.voxelPosition, result.normal, startPosition);
	ivec2 textureCoords = getTextureCoords(result.voxelPosition, result.textureDir);
	fragColor = mipMapSample(texture_sampler, textureCoords, textureIndex, lod)*vec4(ambientLight*normalVariation, 1);

	if (fragColor.a <= 0.1f) fragColor.a = 1; // TODO: Proper alpha handling.

	if (fog.activ) {

		// Underwater fog in lod(assumes that the fog is maximal):
		fragColor = vec4((1 - fragColor.a) * waterFog.color.xyz + fragColor.a * fragColor.xyz, 1);
	}
	fragColor.rgb += mipMapSample(emissionSampler, textureCoords, textureIndex, lod).rgb;

	if (fog.activ) {
		fragColor = calcFog(mvVertexPos, fragColor, fog);
	}
	fragColor.rgb /= 4;
	position = vec4(mvVertexPos, 1);
}
