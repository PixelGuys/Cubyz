#version 430

out vec3 mvVertexPos;
out vec2 outTexCoord;
flat out float textureIndex;
out float outNormalVariation;

uniform int visibilityMask;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 modelPosition;

layout(std430, binding = 0) buffer _animationTimes
{
	int animationTimes[];
};
layout(std430, binding = 1) buffer _animationFrames
{
	int animationFrames[];
};
struct FaceData {
	int encodedPosition;
	int texCoordAndNormals;
};
layout(std430, binding = 3) buffer _faceData
{
	int voxelSize;
	FaceData faceData[];
};

uniform int time;

const float[6] outNormalVariations = float[6](
	1.0, //vec3(0, 1, 0),
	0.8, //vec3(0, -1, 0),
	0.9, //vec3(1, 0, 0),
	0.9, //vec3(-1, 0, 0),
	0.95, //vec3(0, 0, 1),
	0.8 //vec3(0, 0, -1)
);
const vec3[6] normals = vec3[6](
	vec3(0, 1, 0),
	vec3(0, -1, 0),
	vec3(1, 0, 0),
	vec3(-1, 0, 0),
	vec3(0, 0, 1),
	vec3(0, 0, -1)
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
	int encodedPosition = faceData[faceID].encodedPosition;
	int texCoordAndNormals = faceData[faceID].texCoordAndNormals;
	int normal = (texCoordAndNormals >> 24) & 7;
	int texCoordz = texCoordAndNormals & 65535;
	textureIndex = texCoordz + time / animationTimes[texCoordz] % animationFrames[texCoordz];
	outTexCoord = vec2(float(vertexID>>1 & 1)*voxelSize, float(vertexID & 1)*voxelSize);

	ivec3 position = ivec3(
		encodedPosition & 31,
		encodedPosition >> 5 & 31,
		encodedPosition >> 10 & 31
	);
	int octantIndex = (position.x >> 4) | (position.y >> 4)<<1 | (position.z >> 4)<<2;
	if((visibilityMask & 1<<octantIndex) == 0) { // discard face
		gl_Position = vec4(-2, -2, -2, 1);
		return;
	}
	
	position += positionOffset[normal];
	position += ivec3(equal(textureX[normal], ivec3(-1, -1, -1))) + (vertexID>>1 & 1)*textureX[normal];
	position += ivec3(equal(textureY[normal], ivec3(-1, -1, -1))) + (vertexID & 1)*textureY[normal];

	vec3 globalPosition = position*voxelSize + modelPosition;

	vec4 mvPos = viewMatrix*vec4(globalPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	outNormalVariation = outNormalVariations[normal];
	mvVertexPos = mvPos.xyz;
}