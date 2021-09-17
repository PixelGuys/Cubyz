#version 330

layout (location=0)  in int positionAndNormals;
layout (location=1)  in int texCoordAndNormals;

out vec3 mvVertexPos;
out vec3 outTexCoord;
out vec3 outNormal;


uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 modelPosition;
uniform vec3 lowerBounds;
uniform vec3 upperBounds;
uniform float voxelSize;

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
	outTexCoord = vec3(float(texCoordAndNormals>>17 & 1)*voxelSize, float(texCoordAndNormals>>16 & 1)*voxelSize, float(texCoordAndNormals & 65535));
	int x = (positionAndNormals) & 1023;
	int y = (positionAndNormals >> 10) & 1023;
	int z = (positionAndNormals >> 20) & 1023;

	// Only draw faces that are inside the bounds. The others will be clipped using GL_CLIP_DISTANCE0:
	vec3 globalPosition = vec3(x, y, z) + modelPosition;
	globalPosition -= normals[normal]*0.5; // Prevent showing faces that are outside this chunkpiece.
	if(globalPosition.x < lowerBounds.x || globalPosition.x > upperBounds.x
			|| globalPosition.y < lowerBounds.y || globalPosition.y > upperBounds.y
			|| globalPosition.z < lowerBounds.z || globalPosition.z > upperBounds.z) {
		gl_ClipDistance[0] = -1/0.0;
	} else {
		gl_ClipDistance[0] = 1;
	}
	
	globalPosition = vec3(x, y, z) + modelPosition;
	
	vec4 mvPos = viewMatrix*vec4(globalPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	outNormal = normals[normal];
    mvVertexPos = mvPos.xyz;
}