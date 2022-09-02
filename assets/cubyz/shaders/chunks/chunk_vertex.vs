#version 430

out vec3 mvVertexPos;
out vec2 outTexCoord;
flat out float textureIndex;
out vec3 outNormal;


uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 modelPosition;
uniform vec3 lowerBounds;
uniform vec3 upperBounds;

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

const vec3[6] normals = vec3[6](
	vec3(-1, 0, 0),
	vec3(1, 0, 0),
	vec3(0, 0, -1),
	vec3(0, 0, 1),
	vec3(0, -1, 0),
	vec3(0, 1, 0)
);
const ivec3[6] textureX = ivec3[6](
	ivec3(0, 0, 1),
	ivec3(0, 0, -1),
	ivec3(-1, 0, 0),
	ivec3(1, 0, 0),
	ivec3(-1, 0, 0),
	ivec3(1, 0, 0)
);
const ivec3[6] textureY = ivec3[6](
	ivec3(0, -1, 0),
	ivec3(0, -1, 0),
	ivec3(0, -1, 0),
	ivec3(0, -1, 0),
	ivec3(0, 0, 1),
	ivec3(0, 0, 1)
);

void main()
{
	int faceID = gl_VertexID/4;
	int vertexID = gl_VertexID%4;
	int encodedPosition = faceData[faceID].encodedPosition;
	int texCoordAndNormals = faceData[faceID].texCoordAndNormals;
	int normal = (texCoordAndNormals >> 24) & 7;
	int texCoordz = texCoordAndNormals & 65535;
	textureIndex = texCoordz + time / animationTimes[texCoordz] % animationFrames[texCoordz];
	outTexCoord = vec2(float(vertexID>>1 & 1)*voxelSize, float(vertexID & 1)*voxelSize);

	vec3 position = vec3(
		encodedPosition & 63,
		encodedPosition >> 6 & 63,
		encodedPosition >> 12 & 63
	);
	position += vec3(equal(textureX[normal], ivec3(-1, -1, -1))) + (vertexID>>1 & 1)*textureX[normal];
	position += vec3(equal(textureY[normal], ivec3(-1, -1, -1))) + (vertexID & 1)*textureY[normal];

	// Only draw faces that are inside the bounds. The others will be clipped using GL_CLIP_DISTANCE0:
	vec3 globalPosition = position*voxelSize + modelPosition;

	vec4 mvPos = viewMatrix*vec4(globalPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	outNormal = normals[normal];
	mvVertexPos = mvPos.xyz;

	// Check if this vertex is outside the bounds that should be rendered:
	globalPosition -= normals[normal]*0.5; // Prevent showing faces that are outside this chunkpiece.
	if (globalPosition.x < lowerBounds.x || globalPosition.x > upperBounds.x
			|| globalPosition.y < lowerBounds.y || globalPosition.y > upperBounds.y
			|| globalPosition.z < lowerBounds.z || globalPosition.z > upperBounds.z) {
		gl_Position.z = -1/0.0;
	}
}