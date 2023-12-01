#version 430

out vec3 mvVertexPos;
out vec3 light;
flat out int blockType;
flat out int faceNormal;
flat out int isBackFace;
flat out int ditherSeed;
// For raymarching:
out vec3 startPosition;
out vec3 direction;

uniform vec3 ambientLight;
uniform int visibilityMask;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 modelPosition;

struct FaceData {
	int encodedPositionAndNormalsAndPermutation;
	int blockAndModel;
	int light[4];
};
layout(std430, binding = 3) buffer _faceData
{
	FaceData faceData[];
};

struct ModelInfo {
	ivec4 minimum;
	ivec4 maximum;
};

layout(std430, binding = 4) buffer _voxelModels
{
	ModelInfo voxelModels[];
};

uniform int voxelSize;

const vec3[8] mirrorVectors = vec3[8](
	vec3(1, 1, 1),
	vec3(-1, 1, 1),
	vec3(1, -1, 1),
	vec3(-1, -1, 1),
	vec3(1, 1, -1),
	vec3(-1, 1, -1),
	vec3(1, -1, -1),
	vec3(-1, -1, -1)
);
const mat3[8] permutationMatrices = mat3[8](
	mat3(
		1, 0, 0,
		0, 1, 0,
		0, 0, 1
	), // permutationX = 0, permutationYZ = 0
	mat3(
		0, 1, 0,
		1, 0, 0,
		0, 0, 1
	), // permutationX = 1, permutationYZ = 0
	mat3(
		0, 0, 1,
		0, 1, 0,
		1, 0, 0
	), // permutationX = 2, permutationYZ = 0
	mat3(0), // permutationX = 3 (invalid), permutationYZ = 0
	mat3(
		1, 0, 0,
		0, 0, 1,
		0, 1, 0
	), // permutationX = 0, permutationYZ = 1
	mat3(
		0, 1, 0,
		0, 0, 1,
		1, 0, 0
	), // permutationX = 1, permutationYZ = 1
	mat3(
		0, 0, 1,
		1, 0, 0,
		0, 1, 0
	), // permutationX = 2, permutationYZ = 1
	mat3(0) // permutationX = 3 (invalid), permutationYZ = 1
);

const vec3[6] normals = vec3[6](
	vec3(0, 1, 0),
	vec3(0, -1, 0),
	vec3(1, 0, 0),
	vec3(-1, 0, 0),
	vec3(0, 0, 1),
	vec3(0, 0, -1)
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

int convertNormal(int normal, mat3 permutationMatrix, vec3 mirrorVector) {
	vec3 normalVector = normals[normal];
	normalVector = permutationMatrix*(normalVector*mirrorVector);
	if(normalVector.y == 1) return 0;
	if(normalVector.y == -1) return 1;
	if(normalVector.x == 1) return 2;
	if(normalVector.x == -1) return 3;
	if(normalVector.z == 1) return 4;
	if(normalVector.z == -1) return 5;
	return -1;
}

void main() {
	int faceID = gl_VertexID/4;
	int vertexID = gl_VertexID%4;
	int encodedPositionAndNormalsAndPermutation = faceData[faceID].encodedPositionAndNormalsAndPermutation;
	int blockAndModel = faceData[faceID].blockAndModel;
	int fullLight = faceData[faceID].light[vertexID];
	vec3 sunLight = vec3(
		fullLight >> 25 & 31,
		fullLight >> 20 & 31,
		fullLight >> 15 & 31
	);
	vec3 blockLight = vec3(
		fullLight >> 10 & 31,
		fullLight >> 5 & 31,
		fullLight >> 0 & 31
	);
	light = max(sunLight*ambientLight, blockLight)/32;
	isBackFace = encodedPositionAndNormalsAndPermutation>>19 & 1;
	int oldNormal = (encodedPositionAndNormalsAndPermutation >> 20) & 7;
	mat3 permutationMatrix = permutationMatrices[(encodedPositionAndNormalsAndPermutation >> 23) & 7];
	vec3 mirrorVector = mirrorVectors[(encodedPositionAndNormalsAndPermutation >> 26) & 7];
	int normal = convertNormal(oldNormal, permutationMatrix, mirrorVector);
	ditherSeed = encodedPositionAndNormalsAndPermutation & 15;

	blockType = blockAndModel & 65535;
	int modelIndex = blockAndModel >> 16;

	ivec3 position = ivec3(
		encodedPositionAndNormalsAndPermutation & 31,
		encodedPositionAndNormalsAndPermutation >> 5 & 31,
		encodedPositionAndNormalsAndPermutation >> 10 & 31
	);
	int octantIndex = (position.x >> 4) | (position.y >> 4)<<1 | (position.z >> 4)<<2;
	if((visibilityMask & 1<<octantIndex) == 0) { // discard face
		gl_Position = vec4(-2, -2, -2, 1);
		return;
	}
	
	position *= 16;
	position -= ivec3(mirrorVector)*8 - 8;
	position = ivec3(permutationMatrix*(position*mirrorVector));
	position *= voxelSize;
	ivec3 totalOffset = (ivec3(normals[oldNormal])+1)/2;
	totalOffset += ivec3(equal(textureX[oldNormal], ivec3(-1))) + (vertexID>>1 & 1)*textureX[oldNormal];
	totalOffset += ivec3(equal(textureY[oldNormal], ivec3(-1))) + (vertexID & 1)*textureY[oldNormal];
	totalOffset = ivec3(permutationMatrix*(vec3(equal(mirrorVector, vec3(1)))*totalOffset + vec3(equal(mirrorVector, vec3(-1)))*(1 - totalOffset)));
	ivec3 lowerBound = voxelModels[modelIndex].minimum.xyz;
	ivec3 size = voxelModels[modelIndex].maximum.xyz - voxelModels[modelIndex].minimum.xyz;
	size += (voxelSize - 1)*16;
	totalOffset = lowerBound + size*totalOffset;
	position += totalOffset - 16*voxelSize*ivec3(normals[normal]);

	startPosition = (totalOffset)*0.999;

	direction = position.xyz/16.0 + permutationMatrix*(mirrorVector*modelPosition);

	vec3 globalPosition = mirrorVector*(transpose(permutationMatrix)*position)/16.0 + modelPosition;

	vec4 mvPos = viewMatrix*vec4(globalPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	faceNormal = normal;
	mvVertexPos = mvPos.xyz;
}