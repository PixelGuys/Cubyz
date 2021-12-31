#version 430

in vec3 startPosition;
in vec3 direction;
in vec3 cameraSpacePos;
flat in uint voxelModel;
flat in uvec3 size;

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 position;

struct Fog {
	bool activ;
	vec3 color;
	float density;
};

uniform vec3 ambientLight;
uniform vec3 directionalLight;
uniform mat4 projectionMatrix;
uniform float sizeScale;

uniform Fog fog;

layout(std430, binding = 2) buffer _voxelModels
{
    uint voxelModels[];
};

uint getVoxel(uvec3 pos) {
	uint index = (pos.x | pos.y*size.x)*size.z | pos.z;
	return voxelModels[voxelModel + index];
}

vec4 calcFog(vec3 pos, vec4 color, Fog fog) {
	float distance = length(pos);
	float fogFactor = 1.0/exp((distance*fog.density)*(distance*fog.density));
	fogFactor = clamp(fogFactor, 0.0, 1.0);
	vec3 resultColor = mix(fog.color, color.xyz, fogFactor);
	return vec4(resultColor.xyz, color.w + 1 - fogFactor);
}

vec4 decodeColor(uint block) {
	return vec4(block >> 16 & uint(255), block >> 8 & uint(255), block & uint(255), block >> 24 & uint(255))/255.0;
}

void main() {
	// Implementation of "A Fast Voxel Traversal Algorithm for Ray Tracing"  http://www.cse.yorku.ca/~amana/research/grid.pdf
	ivec3 step = ivec3(sign(direction));
	vec3 t1 = (floor(startPosition) - startPosition)/direction;
	vec3 tDelta = 1/(direction);
	vec3 t2 = t1 + tDelta;
	tDelta = abs(tDelta);
	vec3 tMax = max(t1, t2);
	if(direction.x == 0) tMax.x = 1.0/0.0;
	if(direction.y == 0) tMax.y = 1.0/0.0;
	if(direction.z == 0) tMax.z = 1.0/0.0;
	
	uvec3 voxelPosition = uvec3(floor(startPosition));
	vec3 lastNormal;
	uint block = getVoxel(voxelPosition);
	float total_tMax = 0;
	
	uvec3 sizeMask = size - 1;
	
	while(block == 0) {
		if(tMax.x < tMax.y) {
			if(tMax.x < tMax.z) {
				voxelPosition.x += step.x;
				if((voxelPosition.x & sizeMask.x) != voxelPosition.x)
					discard;
				total_tMax = tMax.x;
				tMax.x += tDelta.x;
				lastNormal = vec3(step.x, 0, 0);
			} else {
				voxelPosition.z += step.z;
				if((voxelPosition.z & sizeMask.z) != voxelPosition.z)
					discard;
				total_tMax = tMax.z;
				tMax.z += tDelta.z;
				lastNormal = vec3(0, 0, step.z);
			}
		} else {
			if(tMax.y < tMax.z) {
				voxelPosition.y += step.y;
				if((voxelPosition.y & sizeMask.y) != voxelPosition.y)
					discard;
				total_tMax = tMax.y;
				tMax.y += tDelta.y;
				lastNormal = vec3(0, step.y, 0);
			} else {
				voxelPosition.z += step.z;
				if((voxelPosition.z & sizeMask.z) != voxelPosition.z)
					discard;
				total_tMax = tMax.z;
				tMax.z += tDelta.z;
				lastNormal = vec3(0, 0, step.z);
			}
		}
		block = getVoxel(voxelPosition);
	}
	if(block == 0) discard;
	
	vec3 modifiedCameraSpacePos = cameraSpacePos*(1 + total_tMax*sizeScale*length(direction)/length(cameraSpacePos));
	vec4 projection = projectionMatrix*vec4(modifiedCameraSpacePos, 1);
	float depth = projection.z/projection.w;
	gl_FragDepth = ((gl_DepthRange.diff * depth) + gl_DepthRange.near + gl_DepthRange.far)/2.0;
	
	
	
	vec4 color = decodeColor(block);
	color.a = 1; // No transparency supported!
	color = color*vec4(ambientLight*(1 - dot(directionalLight, lastNormal)), 1);

	if (fog.activ) {
		fragColor = calcFog(modifiedCameraSpacePos, color, fog);
	}
	position = vec4(modifiedCameraSpacePos, 1);
}
