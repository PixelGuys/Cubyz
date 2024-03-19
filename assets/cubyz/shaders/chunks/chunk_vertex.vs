#version 430

out vec3 mvVertexPos;
out vec3 direction;
out vec3 light;
out vec2 uv;
flat out vec3 normal;
flat out int textureIndex;
flat out int isBackFace;
flat out int ditherSeed;

uniform vec3 ambientLight;
uniform int visibilityMask;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 modelPosition;

struct FaceData {
	int encodedPosition;
	int textureAndQuad;
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
	int encodedPosition = faceData[faceID].encodedPosition;
	int textureAndQuad = faceData[faceID].textureAndQuad;
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
	isBackFace = encodedPosition>>19 & 1;
	ditherSeed = encodedPosition & 15;

	textureIndex = textureAndQuad & 65535;
	int quadIndex = textureAndQuad >> 16;

	vec3 position = vec3(
		encodedPosition & 31,
		encodedPosition >> 5 & 31,
		encodedPosition >> 10 & 31
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