#version 430

out vec3 mvVertexPos;
out vec3 direction;
out vec3 light;
out vec2 uv;
flat out vec3 normal;
flat out int blockType;
flat out uint textureSlot;
flat out int isBackFace;
flat out int ditherSeed;

uniform vec3 ambientLight;
uniform int visibilityMask;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 modelPosition;

struct FaceData {
	int encodedPositionAndPermutation;
	int blockAndQuad;
	int light[4];
};
layout(std430, binding = 3) buffer _faceData
{
	FaceData faceData[];
};

struct QuadInfo {
	vec3 normal;
	vec3 corners[4];
	vec2 cornerUV[4];
	uint textureSlot;
};

layout(std430, binding = 4) buffer _quads
{
	QuadInfo quads[];
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
	vec3(0, 0, 1),
	vec3(0, 0, -1),
	vec3(1, 0, 0),
	vec3(-1, 0, 0),
	vec3(0, 1, 0),
	vec3(0, -1, 0)
);
const ivec3[6] textureX = ivec3[6](
	ivec3(1, 0, 0),
	ivec3(-1, 0, 0),
	ivec3(0, -1, 0),
	ivec3(0, 1, 0),
	ivec3(1, 0, 0),
	ivec3(-1, 0, 0)
);
const ivec3[6] textureY = ivec3[6](
	ivec3(0, 1, 0),
	ivec3(0, 1, 0),
	ivec3(0, 0, -1),
	ivec3(0, 0, -1),
	ivec3(0, 0, -1),
	ivec3(0, 0, -1)
);

void main() {
	int faceID = gl_VertexID >> 2;
	int vertexID = gl_VertexID & 3;
	int encodedPositionAndPermutation = faceData[faceID].encodedPositionAndPermutation;
	int blockAndQuad = faceData[faceID].blockAndQuad;
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
	isBackFace = encodedPositionAndPermutation>>19 & 1;
	int oldNormal = (encodedPositionAndPermutation >> 20) & 7;
	mat3 permutationMatrix = permutationMatrices[(encodedPositionAndPermutation >> 23) & 7];
	vec3 mirrorVector = mirrorVectors[(encodedPositionAndPermutation >> 26) & 7];
	ditherSeed = encodedPositionAndPermutation & 15;

	blockType = blockAndQuad & 65535;
	int quadIndex = blockAndQuad >> 16;

	ivec3 position = ivec3(
		encodedPositionAndPermutation & 31,
		encodedPositionAndPermutation >> 5 & 31,
		encodedPositionAndPermutation >> 10 & 31
	);
	int octantIndex = (position.x >> 4) | (position.y >> 4)<<1 | (position.z >> 4)<<2;
	if((visibilityMask & 1<<octantIndex) == 0) { // discard face
		gl_Position = vec4(-2, -2, -2, 1);
		return;
	}

	normal = permutationMatrix*(quads[quadIndex].normal*mirrorVector);
	
	position *= 16;
	position -= ivec3(mirrorVector)*8 - 8;
	position = ivec3(permutationMatrix*(position*mirrorVector));
	position *= voxelSize;
	ivec3 totalOffset = ivec3(16*voxelSize*quads[quadIndex].corners[vertexID]);
	totalOffset = ivec3(permutationMatrix*(vec3(equal(mirrorVector, vec3(1)))*totalOffset + vec3(equal(mirrorVector, vec3(-1)))*(1 - totalOffset)));
	position += totalOffset - 16*voxelSize*ivec3(normal);

	direction = position.xyz/16.0 + permutationMatrix*(mirrorVector*modelPosition);

	vec3 globalPosition = mirrorVector*(transpose(permutationMatrix)*position)/16.0 + modelPosition;

	vec4 mvPos = viewMatrix*vec4(globalPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
	uv = quads[quadIndex].cornerUV[vertexID]*voxelSize;
	textureSlot = quads[quadIndex].textureSlot;
}