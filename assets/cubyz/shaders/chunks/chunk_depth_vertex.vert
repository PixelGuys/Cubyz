#version 460

#include "chunk_data.glsl"
#include "frame_uniforms.glsl"

layout(location = 1) out vec3 direction;
layout(location = 2) out vec2 uv;
layout(location = 3) flat out int textureIndex;
layout(location = 4) flat out int isBackFace;
layout(location = 5) flat out int opaqueInLod;

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

vec3 square(vec3 x) {
	return x*x;
}

void main() {
	int faceID = gl_VertexIndex >> 2;
	int vertexID = gl_VertexIndex & 3;
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

	position += vec3(quads[quadIndex].corners[vertexID][0], quads[quadIndex].corners[vertexID][1], quads[quadIndex].corners[vertexID][2]);
	position *= voxelSize;
	position += vec3(chunks[chunkID].position.xyz - playerPositionInteger);
	position -= playerPositionFraction;

	direction = position;

	gl_Position = lightProjectionMatrix*lightViewMatrix*vec4(position, 1);
	uv = quads[quadIndex].cornerUV[vertexID]*voxelSize;
	opaqueInLod = quads[quadIndex].opaqueInLod;
}
