#version 460

out vec3 mvVertexPos;
out vec3 direction;
out vec3 light;
out vec2 uv;
flat out vec3 normal;
flat out int textureIndex;
flat out int isBackFace;
flat out int ditherSeed;

uniform vec3 ambientLight;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform ivec3 playerPositionInteger;
uniform vec3 playerPositionFraction;

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
	vec3 corners[4];
	vec2 cornerUV[4];
	uint textureSlot;
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
	int visibilityMask;
	int voxelSize;
	uint vertexStartOpaque;
	uint faceCountsByNormalOpaque[7];
	uint lightStartOpaque;
	uint vertexStartTransparent;
	uint vertexCountTransparent;
	uint lightStartTransparent;
	uint visibilityState;
	uint oldVisibilityState;
};

layout(std430, binding = 6) buffer _chunks
{
	ChunkData chunks[];
};

void main() {
	int faceID = gl_VertexID >> 2;
	int vertexID = gl_VertexID & 3;
	int chunkID = gl_BaseInstance;
	int visibilityMask = chunks[chunkID].visibilityMask;
	int voxelSize = chunks[chunkID].voxelSize;
	vec3 modelPosition = vec3(chunks[chunkID].position.xyz - playerPositionInteger) - playerPositionFraction;
	int encodedPositionAndLightIndex = faceData[faceID].encodedPositionAndLightIndex;
	int textureAndQuad = faceData[faceID].textureAndQuad;
#ifdef transparent
	uint lightIndex = chunks[chunkID].lightStartTransparent + 4*(encodedPositionAndLightIndex >> 16);
#else
	uint lightIndex = chunks[chunkID].lightStartOpaque + 4*(encodedPositionAndLightIndex >> 16);
#endif
	uint fullLight = lightData[lightIndex + vertexID];
	vec3 sunLight = vec3(
		fullLight >> 25 & 31u,
		fullLight >> 20 & 31u,
		fullLight >> 15 & 31u
	);
	vec3 blockLight = vec3(
		fullLight >> 10 & 31u,
		fullLight >> 5 & 31u,
		fullLight >> 0 & 31u
	);
	light = max(sunLight*ambientLight, blockLight)/31;
	isBackFace = encodedPositionAndLightIndex>>15 & 1;
	ditherSeed = encodedPositionAndLightIndex & 15;

	textureIndex = textureAndQuad & 65535;
	int quadIndex = textureAndQuad >> 16;

	vec3 position = vec3(
		encodedPositionAndLightIndex & 31,
		encodedPositionAndLightIndex >> 5 & 31,
		encodedPositionAndLightIndex >> 10 & 31
	);
	int octantIndex = (int(position.x) >> 4) | (int(position.y) >> 4)<<1 | (int(position.z) >> 4)<<2;
	if((visibilityMask & 1<<octantIndex) == 0) { // discard face
		gl_Position = vec4(-2, -2, -2, 1);
		return;
	}

	normal = quads[quadIndex].normal;
	
	position += quads[quadIndex].corners[vertexID];
	position *= voxelSize;
	position += modelPosition;

	direction = position;

	vec4 mvPos = viewMatrix*vec4(position, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
	uv = quads[quadIndex].cornerUV[vertexID]*voxelSize;
}
