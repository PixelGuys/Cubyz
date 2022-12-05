#version 430

flat in int blockIndex;
flat in int faceNormal;
flat in int modelIndex;
flat in ivec3 outModelPosition;
// For raymarching:
in vec3 startPosition;
in vec3 direction;

layout(location = 1) out ivec4 fragmentData;

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

struct Palette {
	int materialReference[8];
};

layout(std430, binding = 4) buffer _voxelModels
{
	VoxelModel voxelModels[];
};

layout(std430, binding = 6) buffer _palettes
{
	Palette palettes[];
};


const float[6] normalVariations = float[6](
	1.0, //vec3(0, 1, 0),
	0.88, //vec3(0, -1, 0),
	0.92, //vec3(1, 0, 0),
	0.92, //vec3(-1, 0, 0),
	0.96, //vec3(0, 0, 1),
	0.88 //vec3(0, 0, -1)
);

int getVoxel(int voxelIndex) {
	voxelIndex = (voxelIndex & 0xf) | (voxelIndex>>1 & 0xf0) | (voxelIndex>>2 & 0xf00);
	int shift = 4*(voxelIndex & 7);
	int arrayIndex = voxelIndex >> 3;
	return int(voxelModels[modelIndex].bitPackedData[arrayIndex]>>shift & 15u) - 7;
}

struct RayMarchResult {
	bool hitAThing;
	int normal;
	int palette;
	ivec3 voxelPos;
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
	return RayMarchResult(true, lastNormal, -block, voxelPos);
}

void main() {
	RayMarchResult result = rayMarching(startPosition, direction);
	if(!result.hitAThing) discard;

	int materialIndex = palettes[blockIndex].materialReference[result.palette];
	fragmentData.xyz = outModelPosition + result.voxelPos;
	fragmentData.w = materialIndex | result.normal<<16;
}