#version 430

out vec3 mvVertexPos;
out vec2 outTexCoord;
flat out int textureIndex;
flat out int modelIndex;
flat out int faceNormal;
flat out ivec3 outModelPosition;
// For raymarching:
out vec3 startPosition;
out vec3 direction;

uniform int visibilityMask;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 modelPosition;
uniform ivec3 integerPosition;

layout(std430, binding = 0) buffer _animationTimes
{
	int animationTimes[];
};
layout(std430, binding = 1) buffer _animationFrames
{
	int animationFrames[];
};
struct FaceData {
	int encodedPositionAndNormals;
	int texCoordAndVoxelModel;
};
layout(std430, binding = 3) buffer _faceData
{
	FaceData faceData[];
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

uniform int time;
uniform int voxelSize;

const vec3[6] normals = vec3[6](
	vec3(0, 1, 0),
	vec3(0, -1, 0),
	vec3(1, 0, 0),
	vec3(-1, 0, 0),
	vec3(0, 0, 1),
	vec3(0, 0, -1)
);
const vec3[6] absNormals = vec3[6](
	vec3(0, 1, 0),
	vec3(0, 1, 0),
	vec3(1, 0, 0),
	vec3(1, 0, 0),
	vec3(0, 0, 1),
	vec3(0, 0, 1)
);
const ivec3[6] positionOffset = ivec3[6](
	ivec3(0, 0, 0),
	ivec3(0, 1, 0),
	ivec3(0, 0, 0),
	ivec3(1, 0, 0),
	ivec3(0, 0, 0),
	ivec3(0, 0, 1)
);
const ivec3[6] textureX = ivec3[6](
	ivec3(1, 0, 0),
	ivec3(-1, 0, 0),
	ivec3(0, 0, -1),
	ivec3(0, 0, 1),
	ivec3(1, 0, 0),
	ivec3(-1, 0, 0)
);
const ivec3[6] textureY = ivec3[6](
	ivec3(0, 0, 1),
	ivec3(0, 0, 1),
	ivec3(0, -1, 0),
	ivec3(0, -1, 0),
	ivec3(0, -1, 0),
	ivec3(0, -1, 0)
);

void main() {
	int faceID = gl_VertexID/4;
	int vertexID = gl_VertexID%4;
	int encodedPositionAndNormals = faceData[faceID].encodedPositionAndNormals;
	int texCoordAndVoxelModel = faceData[faceID].texCoordAndVoxelModel;
	int normal = (encodedPositionAndNormals >> 24) & 7;
	int texCoordz = texCoordAndVoxelModel & 65535;
	modelIndex = texCoordAndVoxelModel >> 16;
	textureIndex = texCoordz + time / animationTimes[texCoordz] % animationFrames[texCoordz];
	outTexCoord = vec2(float(vertexID>>1 & 1)*voxelSize, float(vertexID & 1)*voxelSize);

	ivec3 position = ivec3(
		encodedPositionAndNormals & 31,
		encodedPositionAndNormals >> 5 & 31,
		encodedPositionAndNormals >> 10 & 31
	);
	int octantIndex = (position.x >> 4) | (position.y >> 4)<<1 | (position.z >> 4)<<2;
	if((visibilityMask & 1<<octantIndex) == 0) { // discard face
		gl_Position = vec4(-2, -2, -2, 1);
		return;
	}
	
	position *= 16;
	outModelPosition = position - 16*ivec3(normals[normal]) + integerPosition*16;
	ivec3 totalOffset = (ivec3(normals[normal])+1)/2;
	totalOffset += ivec3(equal(textureX[normal], ivec3(-1, -1, -1))) + (vertexID>>1 & 1)*textureX[normal];
	totalOffset += ivec3(equal(textureY[normal], ivec3(-1, -1, -1))) + (vertexID & 1)*textureY[normal];
	ivec3 lowerBound = ivec3(voxelModels[modelIndex].minX, voxelModels[modelIndex].minY, voxelModels[modelIndex].minZ);
	ivec3 size = ivec3(voxelModels[modelIndex].maxX, voxelModels[modelIndex].maxY, voxelModels[modelIndex].maxZ) - lowerBound;
	totalOffset = lowerBound + size*totalOffset;
	position += totalOffset - 16*ivec3(normals[normal]);

	startPosition = (totalOffset)*0.999;

	direction = position.xyz*voxelSize/16.0 + modelPosition + (viewMatrix*vec4(0, 0, 0, 1)).xyz;

	vec3 globalPosition = position*voxelSize/16.0 + modelPosition;

	vec4 mvPos = viewMatrix*vec4(globalPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	faceNormal = normal;
	mvVertexPos = mvPos.xyz;
}