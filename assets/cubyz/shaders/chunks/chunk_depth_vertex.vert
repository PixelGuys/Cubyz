#version 460

layout(location = 1) out vec3 direction;
layout(location = 2) out vec2 uv;
layout(location = 3) flat out vec3 normal;
layout(location = 4) flat out int textureIndex;
layout(location = 5) flat out int isBackFace;
layout(location = 7) flat out int opaqueInLod;

layout(location = 1) uniform mat4 projectionMatrix;
layout(location = 2) uniform mat4 viewMatrix;
layout(location = 3) uniform ivec3 playerPositionInteger;
layout(location = 4) uniform vec3 playerPositionFraction;

struct FaceData {
	int encodedPositionAndLightIndex;
	int textureAndQuad;
};
layout(std430, binding = 3) buffer _faceData
{
	FaceData faceData[];
};

struct QuadInfo {
	vec3 normal;
	float corners[4][3];
	vec2 cornerUV[4];
	uint textureSlot;
	int opaqueInLod;
};

layout(std430, binding = 4) buffer _quads
{
	QuadInfo quads[];
};

layout(std430, binding = 10) buffer _lightData
{
	uint lightData[];
};

struct ChunkData {
	ivec4 position;
	vec4 minPos;
	vec4 maxPos;
	int voxelSize;
	uint lightStart;
	uint vertexStartOpaque;
	uint faceCountsByNormalOpaque[14];
	uint vertexStartTransparent;
	uint vertexCountTransparent;
	uint visibilityState;
	uint oldVisibilityState;
	uint visibilityStateDepth;
	uint oldVisibilityStateDepth;
};

layout(std430, binding = 6) buffer _chunks
{
	ChunkData chunks[];
};

vec3 square(vec3 x) {
	return x*x;
}

void main() {
	int faceID = gl_VertexID >> 2;
	int vertexID = gl_VertexID & 3;
	int chunkID = gl_BaseInstance;
	int voxelSize = chunks[chunkID].voxelSize;
	int encodedPositionAndLightIndex = faceData[faceID].encodedPositionAndLightIndex;
	int textureAndQuad = faceData[faceID].textureAndQuad;
	isBackFace = encodedPositionAndLightIndex>>15 & 1;

	textureIndex = textureAndQuad & 65535;
	int quadIndex = textureAndQuad >> 16;

	vec3 position = vec3(
		encodedPositionAndLightIndex & 31,
		encodedPositionAndLightIndex >> 5 & 31,
		encodedPositionAndLightIndex >> 10 & 31
	);

	normal = quads[quadIndex].normal;

	position += vec3(quads[quadIndex].corners[vertexID][0], quads[quadIndex].corners[vertexID][1], quads[quadIndex].corners[vertexID][2]);
	position *= voxelSize;
	position += vec3(chunks[chunkID].position.xyz - playerPositionInteger);
	position -= playerPositionFraction;

	direction = position;

	gl_Position = projectionMatrix*viewMatrix*vec4(position, 1);
	uv = quads[quadIndex].cornerUV[vertexID]*voxelSize;
	opaqueInLod = quads[quadIndex].opaqueInLod;
}
