#version 430

layout (location=0)  in int positionAndNormals;
layout (location=1)  in int texCoordAndNormals;

out vec3 mvVertexPos;
out vec2 outTexCoord;
flat out float textureIndex;
out vec3 outNormal;


uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 modelPosition;
uniform vec3 lowerBounds;
uniform vec3 upperBounds;
uniform float voxelSize;

layout(std430, binding = 0) buffer _animationTimes
{
    int animationTimes[];
};
layout(std430, binding = 1) buffer _animationFrames
{
    int animationFrames[];
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

void main()
{
	int normal = (texCoordAndNormals >> 24) & 7;
	int texCoordz = texCoordAndNormals & 65535;
	textureIndex = texCoordz + time / animationTimes[texCoordz] % animationFrames[texCoordz];
	outTexCoord = vec2(float(texCoordAndNormals>>17 & 1)*voxelSize, float(texCoordAndNormals>>16 & 1)*voxelSize);
	
	int voxelSize = positionAndNormals >> 18;
	int x = positionAndNormals & 63;
	int y = positionAndNormals >> 6 & 63;
	int z = positionAndNormals >> 12 & 63;
	x *= voxelSize;
	y *= voxelSize;
	z *= voxelSize;

	// Only draw faces that are inside the bounds. The others will be clipped using GL_CLIP_DISTANCE0:
	vec3 globalPosition = vec3(x, y, z) + modelPosition;
	
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