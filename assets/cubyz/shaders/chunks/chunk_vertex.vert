#version 460

layout(location = 0) out vec3 mvVertexPos;
layout(location = 1) out vec3 direction;
layout(location = 2) out vec3 sunLight;
layout(location = 3) out vec3 blockLight;
layout(location = 4) out vec2 uv;
layout(location = 5) out vec3 shadowPos;
layout(location = 6) flat out vec3 normal;
layout(location = 7) flat out int textureIndex;
layout(location = 8) flat out int isBackFace;
layout(location = 9) flat out float distanceForLodCheck;
layout(location = 10) flat out int opaqueInLod;
layout(location = 11) flat out mat4 worldToQuad;
layout(location = 15) flat out mat3 uvTransform;

layout(location = 0) uniform vec3 ambientLight;
layout(location = 1) uniform mat4 projectionMatrix;
layout(location = 2) uniform mat4 viewMatrix;
layout(location = 3) uniform ivec3 playerPositionInteger;
layout(location = 4) uniform vec3 playerPositionFraction;
layout(location = 8) uniform mat4 lightProjectionMatrix;
layout(location = 9) uniform mat4 lightViewMatrix;

#ifdef ENTITY
layout(location = 14) uniform mat4 modelMatrix;
#endif

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

#include "chunk_data.glsl"

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
	uint lightIndex = chunks[chunkID].lightStart + 4*(encodedPositionAndLightIndex >> 16);
	uint fullLight = lightData[lightIndex + vertexID];
	sunLight = vec3(
		fullLight >> 25 & 31u,
		fullLight >> 20 & 31u,
		fullLight >> 15 & 31u
	) * ambientLight;
	blockLight = vec3(
		fullLight >> 10 & 31u,
		fullLight >> 5 & 31u,
		fullLight >> 0 & 31u
	);
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
#ifdef ENTITY
	// Offset by one to account for block position in chunk
	position = (modelMatrix*vec4(position - vec3(1), 1)).xyz + vec3(1);
#endif
	position *= voxelSize;
	position += vec3(chunks[chunkID].position.xyz - playerPositionInteger);
	position -= playerPositionFraction;

	direction = position;

	vec4 mvPos = viewMatrix*vec4(position, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
	distanceForLodCheck = length(mvPos.xyz) + voxelSize;
	uv = quads[quadIndex].cornerUV[vertexID]*voxelSize;
	opaqueInLod = quads[quadIndex].opaqueInLod;

	shadowPos = position + normal * 0.03;

	vec3 p0 = vec3(quads[quadIndex].corners[0][0], quads[quadIndex].corners[0][1], quads[quadIndex].corners[0][2]);
	vec3 p1 = vec3(quads[quadIndex].corners[1][0], quads[quadIndex].corners[1][1], quads[quadIndex].corners[1][2]);
	vec3 p3 = vec3(quads[quadIndex].corners[3][0], quads[quadIndex].corners[3][1], quads[quadIndex].corners[3][2]);
	
	vec2 uv0 = vec2(quads[quadIndex].cornerUV[0][0], quads[quadIndex].cornerUV[0][1]);
	vec2 uv1 = vec2(quads[quadIndex].cornerUV[1][0], quads[quadIndex].cornerUV[1][1]);
	vec2 uv3 = vec2(quads[quadIndex].cornerUV[3][0], quads[quadIndex].cornerUV[3][1]);
	
	vec3 u = p1 - p0;
	vec3 v = p3 - p0;
	mat3 invBasis = inverse(mat3(u, v, cross(u,v)));

	vec2 du = uv1 - uv0;
	vec2 dv = uv3 - uv0;

	uvTransform = mat3(
		vec3(du, 0.0),
		vec3(dv, 0.0),
		vec3(uv0, 1.0)
	);

	worldToQuad = mat4(
		vec4(invBasis[0], 0),
		vec4(invBasis[1], 0),
		vec4(invBasis[2], 0),
		vec4(-(invBasis * p0),1)
	);
}
