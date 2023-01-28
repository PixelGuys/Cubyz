#version 430

layout (location=0)  in int positionAndNormals;

out vec3 startPosition;
out vec3 direction;
out vec3 cameraSpacePos;
flat out int faceNormal;
flat out uint voxelModel;
flat out uvec3 size;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat4 modelMatrix;
uniform int modelIndex;
uniform float sizeScale;

layout(std430, binding = 2) buffer _voxelModels
{
    uint voxelModels[];
};

void main() {
	int x = positionAndNormals >> 2 & 1;
	int y = positionAndNormals >> 1 & 1;
	int z = positionAndNormals >> 0 & 1;
	faceNormal = positionAndNormals >> 3;
	uint voxelModelIndex = modelIndex;
	size.x = voxelModels[voxelModelIndex++];
	size.y = voxelModels[voxelModelIndex++];
	size.z = voxelModels[voxelModelIndex++];
	voxelModel = voxelModelIndex;
	
	startPosition.x = float(size.x)*0.999*x;
	startPosition.y = float(size.y)*0.999*y;
	startPosition.z = float(size.z)*0.999*z;
	
	vec4 worldSpace = modelMatrix*vec4(vec3(x*size.x, y*size.y, z*size.z)*sizeScale + sizeScale/2, 1);
	direction = (transpose(mat3(modelMatrix))*worldSpace.xyz).xyz;
	
	vec4 cameraSpace = viewMatrix*worldSpace;
	gl_Position = projectionMatrix*cameraSpace;
	cameraSpacePos = cameraSpace.xyz;
}
