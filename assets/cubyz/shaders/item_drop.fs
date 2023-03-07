#version 430

in vec3 startPosition;
in vec3 direction;
in vec3 cameraSpacePos;
flat in int faceNormal;
flat in int voxelModel;
flat in int blockType;
flat in uvec3 lower;
flat in uvec3 upper;

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 position;

struct Fog {
	bool activ;
	vec3 color;
	float density;
};

uniform vec3 ambientLight;
uniform mat4 projectionMatrix;
uniform float sizeScale;
uniform int time;

uniform Fog fog;

const float[6] normalVariations = float[6](
	1.0, //vec3(0, 1, 0),
	0.80, //vec3(0, -1, 0),
	0.9, //vec3(1, 0, 0),
	0.9, //vec3(-1, 0, 0),
	0.95, //vec3(0, 0, 1),
	0.85 //vec3(0, 0, -1)
);

vec4 calcFog(vec3 pos, vec4 color, Fog fog) {
	float distance = length(pos);
	float fogFactor = 1.0/exp((distance*fog.density)*(distance*fog.density));
	fogFactor = clamp(fogFactor, 0.0, 1.0);
	vec3 resultColor = mix(fog.color, color.xyz, fogFactor);
	return vec4(resultColor.xyz, color.w + 1 - fogFactor);
}

// blockDrops ------------------------------------------------------------------------------------------------------------------------

const vec3[6] normals = vec3[6](
	vec3(0, 1, 0),
	vec3(0, -1, 0),
	vec3(1, 0, 0),
	vec3(-1, 0, 0),
	vec3(0, 0, 1),
	vec3(0, 0, -1)
);

#define modelSize 16
struct VoxelModel {
	ivec4 minimum;
	ivec4 maximum;
	uint bitPackedData[modelSize*modelSize*modelSize/8];
};

struct AnimationData {
	int frames;
	int time;
};

layout(std430, binding = 0) buffer _animation
{
	AnimationData animation[];
};
layout(std430, binding = 1) buffer _textureIndices
{
	int textureIndices[][6];
};
layout(std430, binding = 4) buffer _blockVoxelModels
{
	VoxelModel blockVoxelModels[];
};
uniform sampler2DArray texture_sampler;
uniform sampler2DArray emissionSampler;

int getVoxel(int voxelIndex) {
	voxelIndex = (voxelIndex & 0xf) | (voxelIndex>>1 & 0xf0) | (voxelIndex>>2 & 0xf00);
	int shift = 4*(voxelIndex & 7);
	int arrayIndex = voxelIndex >> 3;
	return (int(blockVoxelModels[voxelModel].bitPackedData[arrayIndex])>>shift & 15) - 6;
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
	vec3 modifiedCameraSpacePos = cameraSpacePos*(1 + total_tMax*sizeScale*length(direction)/length(cameraSpacePos));
	vec4 projection = projectionMatrix*vec4(modifiedCameraSpacePos, 1);
	float depth = projection.z/projection.w;
	gl_FragDepth = ((gl_DepthRange.diff * depth) + gl_DepthRange.near + gl_DepthRange.far)/2.0;
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
	vec3 varianceX = dFdx(direction);
	vec3 varianceY = dFdx(direction);
	varianceX += direction;
	varianceX = varianceX*length(direction)/length(varianceX);
	varianceX -= direction;
	varianceY += direction;
	varianceY = varianceY*length(direction)/length(varianceY);
	varianceY -= direction;
	vec3 variance = abs(varianceX) + abs(varianceY);
	return 8*length(variance);
}

vec4 mipMapSample(sampler2DArray texture, ivec2 textureCoords, int textureIndex, float lod) { // TODO: anisotropic filtering?
	int lowerLod = int(floor(lod));
	int higherLod = lowerLod+1;
	float interpolation = lod - lowerLod;
	vec4 lower = texelFetch(texture, ivec3(textureCoords >> lowerLod, textureIndex), lowerLod);
	vec4 higher = texelFetch(texture, ivec3(textureCoords >> higherLod, textureIndex), higherLod);
	return higher*interpolation + (1 - interpolation)*lower;
}

void mainBlockDrop() {
	RayMarchResult result;
	float variance = perpendicularFwidth(direction);
	if(variance <= 4.0) {
		result = rayMarching(startPosition, direction);
	} else {
		result = RayMarchResult(true, faceNormal, faceNormal, ivec3(startPosition)); // At some point it doesn't make sense to even draw the model.
	}
	if(!result.hitAThing) discard;
	int textureIndex = textureIndices[blockType][result.textureDir];
	textureIndex = textureIndex + time / animation[textureIndex].time % animation[textureIndex].frames;
	float normalVariation = normalVariations[result.normal];
	float lod = getLod(result.voxelPosition, result.normal, direction, variance);
	ivec2 textureCoords = getTextureCoords(result.voxelPosition, result.textureDir);
	fragColor = mipMapSample(texture_sampler, textureCoords, textureIndex, lod)*vec4(ambientLight*normalVariation, 1);

	if (fragColor.a <= 0.1f) fragColor.a = 1; // TODO: Proper alpha handling.

	fragColor.rgb += mipMapSample(emissionSampler, textureCoords, textureIndex, lod).rgb;

	if (fog.activ) {
		fragColor = calcFog(startPosition, fragColor, fog);
	}
	fragColor.rgb /= 4;
	position = vec4(startPosition, 1);
}

// itemDrops -------------------------------------------------------------------------------------------------------------------------

layout(std430, binding = 2) buffer _itemVoxelModels
{
    uint itemVoxelModels[];
};

uint getVoxel(uvec3 pos) {
	uint index = (pos.x | pos.y*upper.x)*upper.z | pos.z;
	return itemVoxelModels[voxelModel + index];
}

vec4 decodeColor(uint block) {
	return vec4(block >> 16 & uint(255), block >> 8 & uint(255), block & uint(255), block >> 24 & uint(255))/255.0;
}

void mainItemDrop() {
	// Implementation of "A Fast Voxel Traversal Algorithm for Ray Tracing"  http://www.cse.yorku.ca/~amana/research/grid.pdf
	ivec3 step = ivec3(sign(direction));
	vec3 t1 = (floor(startPosition) - startPosition)/direction;
	vec3 tDelta = 1/direction;
	vec3 t2 = t1 + tDelta;
	tDelta = abs(tDelta);
	vec3 tMax = max(t1, t2);
	if(direction.x == 0) tMax.x = 1.0/0.0;
	if(direction.y == 0) tMax.y = 1.0/0.0;
	if(direction.z == 0) tMax.z = 1.0/0.0;
	
	uvec3 voxelPosition = uvec3(floor(startPosition));
	int lastNormal = faceNormal;
	uint block = getVoxel(voxelPosition);
	float total_tMax = 0;
	
	uvec3 sizeMask = upper - 1;
	
	while(block == 0) {
		if(tMax.x < tMax.y) {
			if(tMax.x < tMax.z) {
				voxelPosition.x += step.x;
				if((voxelPosition.x & sizeMask.x) != voxelPosition.x)
					discard;
				total_tMax = tMax.x;
				tMax.x += tDelta.x;
				lastNormal = 2 + (1 + int(step.x))/2;
			} else {
				voxelPosition.z += step.z;
				if((voxelPosition.z & sizeMask.z) != voxelPosition.z)
					discard;
				total_tMax = tMax.z;
				tMax.z += tDelta.z;
				lastNormal = 4 + (1 + int(step.z))/2;
			}
		} else {
			if(tMax.y < tMax.z) {
				voxelPosition.y += step.y;
				if((voxelPosition.y & sizeMask.y) != voxelPosition.y)
					discard;
				total_tMax = tMax.y;
				tMax.y += tDelta.y;
				lastNormal = 0 + (1 + int(step.y))/2;
			} else {
				voxelPosition.z += step.z;
				if((voxelPosition.z & sizeMask.z) != voxelPosition.z)
					discard;
				total_tMax = tMax.z;
				tMax.z += tDelta.z;
				lastNormal = 4 + (1 + int(step.z))/2;
			}
		}
		block = getVoxel(voxelPosition);
	}
	if(block == 0) discard;
	
	vec3 modifiedCameraSpacePos = cameraSpacePos*(1 + total_tMax*sizeScale*length(direction)/length(cameraSpacePos));
	vec4 projection = projectionMatrix*vec4(modifiedCameraSpacePos, 1);
	float depth = projection.z/projection.w;
	gl_FragDepth = ((gl_DepthRange.diff * depth) + gl_DepthRange.near + gl_DepthRange.far)/2.0;
	
	
	
	vec4 color = decodeColor(block);
	color.a = 1; // No transparency supported!
	color = color*vec4(ambientLight*normalVariations[lastNormal], 1);

	if (fog.activ) {
		fragColor = calcFog(modifiedCameraSpacePos, color, fog);
	}
	fragColor.rgb /= 4;
	position = vec4(modifiedCameraSpacePos, 1);
}

void main() {
	if(blockType != 0) {
		mainBlockDrop();
	} else {
		mainItemDrop();
	}
}
