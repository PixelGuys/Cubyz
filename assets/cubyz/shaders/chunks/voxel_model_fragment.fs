#version 450

in vec3 mvVertexPos;
in vec3 chunkPos;
in vec3 light; // TODO: This doesn't work here.
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

layout(location = 0) out vec4 fragColor;

#define modelSize 16
struct VoxelModel {
	ivec4 minimum;
	ivec4 maximum;
	uint bitPackedData[modelSize*modelSize*modelSize/32];
	uint bitPackedTextureData[modelSize*modelSize*modelSize/8];
};

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
layout(std430, binding = 4) buffer _voxelModels
{
	VoxelModel voxelModels[];
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

int getVoxel(ivec3 voxelPos) {
	voxelPos &= 15;
	int voxelIndex = (voxelPos.x << 8) | (voxelPos.y << 4) | (voxelPos.z);
	int shift = (voxelIndex & 31);
	int arrayIndex = voxelIndex >> 5;
	return (int(voxelModels[modelIndex].bitPackedData[arrayIndex])>>shift & 1);
}

int getTexture(ivec3 voxelPos) {
	voxelPos &= 15;
	int voxelIndex = (voxelPos.x << 8) | (voxelPos.y << 4) | (voxelPos.z);
	int shift = 4*(voxelIndex & 7);
	int arrayIndex = voxelIndex >> 3;
	return (int(voxelModels[modelIndex].bitPackedTextureData[arrayIndex])>>shift & 15);
}

struct RayMarchResult {
	bool hitAThing;
	int normal;
	int textureDir;
	ivec3 voxelPosition;
};

RayMarchResult rayMarching(vec3 startPosition, vec3 direction) { // TODO: Mipmapped voxel models. (or maybe just remove them when they are far enough away?)
	// Branchless implementation of "A Fast Voxel Traversal Algorithm for Ray Tracing"  http://www.cse.yorku.ca/~amana/research/grid.pdf
	if(direction.x == 0) {
		direction.x = 1e-10;
	}
	if(direction.y == 0) {
		direction.y = 1e-10;
	}
	if(direction.z == 0) {
		direction.z = 1e-10;
	}
	vec3 step = sign(direction);
	ivec3 stepi = ivec3(step);
	vec3 t1 = (floor(startPosition) - startPosition)/direction;
	vec3 tDelta = 1/direction;
	vec3 t2 = t1 + tDelta;
	tDelta = abs(tDelta);
	vec3 tMax = max(t1, t2);
	
	ivec3 voxelPos = ivec3(floor(startPosition));

	ivec3 compare = mix(-maxPos, minPos, lessThan(direction, vec3(0)));
	ivec3 inversionMasks = mix(ivec3(~0), ivec3(0), lessThan(direction, vec3(0)));

	int lastNormal = faceNormal;
	int block = getVoxel(voxelPos);
	
	int size = 16;
	ivec3 sizeMask = ivec3(size - 1);
	vec3 lastStep = vec3(0, 0, 0);
	while(block != 0) {
		bvec3 gt1 = lessThanEqual(tMax.xyz, tMax.yzx);
		bvec3 gt2 = lessThanEqual(tMax.xyz, tMax.zxy);
		bvec3 and = bvec3(gt1.x && gt2.x, gt1.y && gt2.y, gt1.z && gt2.z);
		lastStep = vec3(and);
		voxelPos += -ivec3(and) & stepi;
		tMax += lastStep*tDelta;
		/*
		Here I use a trick to avoid integer multiplication.
		The correct equation would be
		  sign*pos > compare
		→ ((sign > 0) ? pos : -pos) > compare // Expanding the left hand side (sign != 0 for all practical purposes)
		→ ((sign > 0) ? pos : ~pos+1) > compare // 2's complement
		→ ((sign > 0) ? pos : ~pos) > compare2 // putting the +1 into the compare constant
		→ inversionMasks ^ pos > compare2 // xor can be used to conditionally invert a number
		*/
		if(any(lessThan(voxelPos^inversionMasks, compare)))
			return RayMarchResult(false, 0, 0, ivec3(0, 0, 0));
		block = getVoxel(voxelPos);
	}
	if(lastStep.x != 0) {
		lastNormal = 2 + int(step.x == 1);
	} else if(lastStep.y != 0) {
		lastNormal = 0 + int(step.y == 1);
	} else if(lastStep.z != 0) {
		lastNormal = 4 + int(step.z == 1);
	}
	int textureDir = getTexture(voxelPos);
	if(textureDir == 6) {
		textureDir = lastNormal;
	}
	return RayMarchResult(true, lastNormal, textureDir, voxelPos & 15);
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

vec4 mipMapSample(sampler2DArray texture, ivec2 textureCoords, uint textureIndex, float lod) { // TODO: anisotropic filtering?
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
	const float threshold = 1;
	const float interpolationRegion = 1.25;
	float interp = (variance - threshold)/threshold/(interpolationRegion - 1);
	if(!passDitherTest(interp)) {
		result = rayMarching(startPosition, direction);
	} else {
		result = RayMarchResult(true, faceNormal, faceNormal, ivec3(startPosition) & 15); // At some point it doesn't make sense to even draw the model.
	}
	if(!result.hitAThing) discard;
	uint textureIndex = textureData[blockType].textureIndices[result.textureDir];
	float normalVariation = normalVariations[result.normal];
	float lod = getLod(result.voxelPosition, result.normal, direction, variance);
	ivec2 textureCoords = getTextureCoords(result.voxelPosition, result.textureDir);
	vec3 pos = chunkPos + vec3(result.voxelPosition)/16.0 + 1.0/32.0;
	vec3 light = getLight(pos, normals[result.normal]);
	fragColor = mipMapSample(texture_sampler, textureCoords, textureIndex, lod)*vec4(light*normalVariation, 1);

	if(!passDitherTest(fragColor.a)) discard;
	fragColor.a = 1;

	fragColor.rgb += mipMapSample(emissionSampler, textureCoords, textureIndex, lod).rgb;
	// TODO: Update the depth.
}