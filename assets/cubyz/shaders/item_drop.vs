#version 430

layout (location=0)  in int positionAndNormals;

out vec3 startPosition;
out vec3 direction;
out vec3 cameraSpacePos;
flat out int faceNormal;
flat out int voxelModel;
flat out int blockType;
flat out uvec3 lower;
flat out uvec3 upper;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat4 modelMatrix;
uniform int modelIndex;
uniform int block;
uniform float sizeScale;

layout(std430, binding = 2) buffer _itemVoxelModels
{
	uint itemVoxelModels[];
};

#define modelSize 16
struct VoxelModel {
	ivec4 minimum;
	ivec4 maximum;
	uint bitPackedData[modelSize*modelSize*modelSize/8];
};

layout(std430, binding = 4) buffer _blockVoxelModels
{
	VoxelModel blockVoxelModels[];
};

void main() {
	ivec3 pos = ivec3 (
		positionAndNormals >> 2 & 1,
		positionAndNormals >> 1 & 1,
		positionAndNormals >> 0 & 1
	);
	faceNormal = positionAndNormals >> 3;
	int voxelModelIndex = modelIndex;
	bool isBlock = block != 0;
	if(isBlock) {
		lower = uvec3(blockVoxelModels[voxelModelIndex].minimum.xyz);
		upper = uvec3(blockVoxelModels[voxelModelIndex].maximum.xyz);
	} else {
		upper.x = itemVoxelModels[voxelModelIndex++];
		upper.y = itemVoxelModels[voxelModelIndex++];
		upper.z = itemVoxelModels[voxelModelIndex++];
		lower = uvec3(0);
	}
	voxelModel = voxelModelIndex;
	blockType = block;
	
	startPosition = lower + vec3(upper - lower)*0.999*pos;
	
	vec4 worldSpace = modelMatrix*vec4(pos*(upper - lower)*sizeScale + sizeScale/2, 1);
	direction = (transpose(mat3(modelMatrix))*worldSpace.xyz).xyz;
	
	vec4 cameraSpace = viewMatrix*worldSpace;
	gl_Position = projectionMatrix*cameraSpace;
	cameraSpacePos = cameraSpace.xyz;
}
