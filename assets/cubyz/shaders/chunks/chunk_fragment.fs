#version 430

in vec3 mvVertexPos;
in vec2 outTexCoord;
flat in int textureIndex;
flat in int faceNormal;
flat in int modelIndex;
// For raymarching:
in vec3 startPosition;
in vec3 direction;

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

#define modelSize 16
struct VoxelModel {
	uint minX, maxX;
	uint minY, maxY;
	uint minZ, maxZ;
	uint bitPackedData[modelSize*modelSize*modelSize/8];
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

uint getVoxel(int voxelIndex) {
	voxelIndex = (voxelIndex & 0xf) | (voxelIndex>>1 & 0xf0) | (voxelIndex>>2 & 0xf00);
	int shift = 4*(voxelIndex & 7);
	int arrayIndex = voxelIndex >> 3;
	return (voxelModels[modelIndex].bitPackedData[arrayIndex]>>shift & 15u);
}

struct RayMarchResult {
	bool hitAThing;
	int normal;
	ivec3 voxelPosition;
};

RayMarchResult rayMarching(vec3 startPosition, vec3 direction) {
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
	uint block = getVoxel(voxelIndex);
	float total_tMax = 0;
	
	int size = 16;
	ivec3 sizeMask = ivec3(size - 1);
	int it = 0;
	while(block != 0 && it < 48) {
		it++;
		vec3 tNext = tMax + block*tDelta;
		total_tMax = min(tNext.x, min(tNext.y, tNext.z));
		vec3 missingSteps = floor((total_tMax - tMax)/tDelta + 0.00001);
		voxelIndex += int(dot(missingSteps, stepInIndex));
		tMax += missingSteps*tDelta;
		if((voxelIndex & overflowMask) != 0)
			return RayMarchResult(false, 0, ivec3(0, 0, 0));
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
	return RayMarchResult(true, lastNormal, voxelPos);
}

vec2 getTextureCoords(ivec3 voxelPosition, int normal) {
	switch(normal) {
		case 0:
			return vec2(15 - voxelPosition.x, voxelPosition.z)/16.0;
		case 1:
			return vec2(voxelPosition.x, voxelPosition.z)/16.0;
		case 2:
			return vec2(15 - voxelPosition.z, voxelPosition.y)/16.0;
		case 3:
			return vec2(voxelPosition.z, voxelPosition.y)/16.0;
		case 4:
			return vec2(voxelPosition.x, voxelPosition.y)/16.0;
		case 5:
			return vec2(15 - voxelPosition.x, voxelPosition.y)/16.0;
	}
}

void main() {
	RayMarchResult result = rayMarching(startPosition, direction);
	if(!result.hitAThing) discard;
	float normalVariation = normalVariations[result.normal];
	fragColor = texture(texture_sampler, vec3(getTextureCoords(result.voxelPosition, result.normal), textureIndex))*vec4(ambientLight*normalVariation, 1);

	if (fragColor.a <= 0.1f) fragColor.a = 1; // TODO: Proper alpha handling.

	if (fog.activ) {

		// Underwater fog in lod(assumes that the fog is maximal):
		fragColor = vec4((1 - fragColor.a) * waterFog.color.xyz + fragColor.a * fragColor.xyz, 1);
	}
	fragColor.rgb += texture(emissionSampler, vec3(getTextureCoords(result.voxelPosition, result.normal), textureIndex)).rgb;

	if (fog.activ) {
		fragColor = calcFog(mvVertexPos, fragColor, fog);
	}
	fragColor.rgb /= 4;
	position = vec4(mvVertexPos, 1);
}
