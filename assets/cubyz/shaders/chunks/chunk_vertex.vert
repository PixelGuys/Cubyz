#version 460

layout(location = 0) out vec3 mvVertexPos;
layout(location = 1) out vec3 direction;
layout(location = 2) out vec2 uv;
layout(location = 3) flat out vec3 normal;
layout(location = 4) flat out uint textureIndexOffset;
layout(location = 5) flat out int isBackFace;
layout(location = 6) flat out float distanceForLodCheck;
layout(location = 7) flat out int opaqueInLod;
layout(location = 8) flat out uint lightBufferIndex;
layout(location = 9) flat out uvec2 lightArea;
layout(location = 10) out vec2 lightPosition;

layout(location = 1) uniform mat4 projectionMatrix;
layout(location = 2) uniform mat4 viewMatrix;
layout(location = 3) uniform ivec3 playerPositionInteger;
layout(location = 4) uniform vec3 playerPositionFraction;

struct FaceData {
	int encodedPosition;
	int textureAndQuad;
	int lightIndex;
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
	uint textureStartOpaque;
	uint vertexStartTransparent;
	uint vertexCountTransparent;
	uint textureStartTransparent;
	uint visibilityState;
	uint oldVisibilityState;
};

layout(std430, binding = 6) buffer _chunks
{
	ChunkData chunks[];
};

vec3 corner(int quadIndex, int index) {
	return vec3(quads[quadIndex].corners[index][0], quads[quadIndex].corners[index][1], quads[quadIndex].corners[index][2]);
}

void main() {
	int faceID = gl_VertexID >> 2;
	int vertexID = gl_VertexID & 3;
	int chunkID = gl_BaseInstance;
	int voxelSize = chunks[chunkID].voxelSize;
	int encodedPosition = faceData[faceID].encodedPosition;
	int textureAndQuad = faceData[faceID].textureAndQuad;
	uvec2 quadSize = uvec2(
		(encodedPosition >> 16 & 31) + 1,
		(encodedPosition >> 21 & 31) + 1
	);
	lightBufferIndex = chunks[chunkID].lightStart + 4*faceData[faceID].lightIndex;
	lightArea = quadSize + uvec2(1, 1);
	lightPosition = vec2(vertexID >> 1, vertexID & 1)*quadSize;
	isBackFace = encodedPosition>>15 & 1;

#ifdef transparent
	textureIndexOffset = chunks[chunkID].textureStartTransparent + uint(textureAndQuad & 65535);
#else
	textureIndexOffset = chunks[chunkID].textureStartOpaque + uint(textureAndQuad & 65535);
#endif
	int quadIndex = textureAndQuad >> 16;

	vec3 position = vec3(
		encodedPosition & 31,
		encodedPosition >> 5 & 31,
		encodedPosition >> 10 & 31
	);

	normal = quads[quadIndex].normal;

	vec3 cornerPosition = corner(quadIndex, 0);
	vec2 uvCornerPosition = quads[quadIndex].cornerUV[0];
	if((vertexID & 2) != 0) {
		cornerPosition += (corner(quadIndex, 2) - corner(quadIndex, 0))*quadSize.x;
		uvCornerPosition += (quads[quadIndex].cornerUV[2] - quads[quadIndex].cornerUV[0])*quadSize.x;
	}
	if((vertexID & 1) != 0) {
		cornerPosition += (corner(quadIndex, vertexID) - corner(quadIndex, vertexID & 2))*quadSize.y;
		uvCornerPosition += (quads[quadIndex].cornerUV[vertexID] - quads[quadIndex].cornerUV[vertexID & 2])*quadSize.y;
	}
	position += cornerPosition;
	position *= voxelSize;
	position += vec3(chunks[chunkID].position.xyz - playerPositionInteger);
	position -= playerPositionFraction;

	direction = position;

	vec4 mvPos = viewMatrix*vec4(position, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
	distanceForLodCheck = length(mvPos.xyz) + voxelSize;
	uv = uvCornerPosition*voxelSize;
	opaqueInLod = quads[quadIndex].opaqueInLod;
}
