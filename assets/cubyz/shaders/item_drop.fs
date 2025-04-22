#version 430

in vec3 startPosition;
in vec3 direction;
in vec3 cameraSpacePos;
in vec2 uv;
flat in int faceNormalIndex;
flat in vec3 faceNormal;
flat in int voxelModel;
flat in int textureIndex;
flat in uvec3 lower;
flat in uvec3 upper;

layout(location = 0) out vec4 fragColor;

uniform vec3 ambientLight;
uniform mat4 projectionMatrix;
uniform float sizeScale;

uniform sampler2DArray texture_sampler;
uniform sampler2DArray emissionSampler;
uniform sampler2DArray reflectivityAndAbsorptionSampler;
uniform samplerCube reflectionMap;
uniform float reflectionMapSize;
uniform float contrast;

const float[6] normalVariations = float[6](
	1.0,
	0.80,
	0.9,
	0.9,
	0.95,
	0.85
);

layout(std430, binding = 1) buffer _animatedTexture
{
	float animatedTexture[];
};

// block drops -------------------------------------------------------------------------------------------------------------------------

float lightVariation(vec3 normal) {
	const vec3 directionalPart = vec3(0, contrast/2, contrast);
	const float baseLighting = 1 - contrast;
	return baseLighting + dot(normal, directionalPart);
}

vec4 fixedCubeMapLookup(vec3 v) { // Taken from http://the-witness.net/news/2012/02/seamless-cube-map-filtering/
	float M = max(max(abs(v.x), abs(v.y)), abs(v.z));
	float scale = (reflectionMapSize - 1)/reflectionMapSize;
	if (abs(v.x) != M) v.x *= scale;
	if (abs(v.y) != M) v.y *= scale;
	if (abs(v.z) != M) v.z *= scale;
	return texture(reflectionMap, v);
}

float ditherThresholds[16] = float[16] (
	1/17.0, 9/17.0, 3/17.0, 11/17.0,
	13/17.0, 5/17.0, 15/17.0, 7/17.0,
	4/17.0, 12/17.0, 2/17.0, 10/17.0,
	16/17.0, 8/17.0, 14/17.0, 6/17.0
);

bool passDitherTest(float alpha) {
	ivec2 screenPos = ivec2(gl_FragCoord.xy);
	screenPos &= 3;
	return alpha > ditherThresholds[screenPos.x*4 + screenPos.y];
}

void mainBlockDrop() {
	float animatedTextureIndex = animatedTexture[textureIndex];
	float normalVariation = lightVariation(faceNormal);
	vec3 textureCoords = vec3(uv, animatedTextureIndex);

	float reflectivity = texture(reflectivityAndAbsorptionSampler, textureCoords).a;
	float fresnelReflection = (1 + dot(normalize(direction), faceNormal));
	fresnelReflection *= fresnelReflection;
	fresnelReflection *= min(1, 2*reflectivity); // Limit it to 2*reflectivity to avoid making every block reflective.
	reflectivity = reflectivity*fixedCubeMapLookup(reflect(direction, faceNormal)).x;
	reflectivity = reflectivity*(1 - fresnelReflection) + fresnelReflection;

	vec3 pixelLight = ambientLight*max(vec3(normalVariation), texture(emissionSampler, textureCoords).r*4);
	fragColor = texture(texture_sampler, textureCoords)*vec4(pixelLight, 1);
	fragColor.rgb += reflectivity*pixelLight;

	if(!passDitherTest(fragColor.a)) discard;
	fragColor.a = 1;
	gl_FragDepth = gl_FragCoord.z;
}

// itemDrops -------------------------------------------------------------------------------------------------------------------------

layout(std430, binding = 2) buffer _modelInfo
{
	uint modelInfo[];
};

uint getVoxel(uvec3 pos) {
	uint index = (pos.x | pos.y*upper.x)*upper.z | pos.z;
	return modelInfo[voxelModel + index];
}

vec4 decodeColor(uint block) {
	return vec4(block >> 16 & uint(255), block >> 8 & uint(255), block & uint(255), block >> 24 & uint(255))/255.0;
}

void mainItemDrop() {
	// Implementation of "A Fast Voxel Traversal Algorithm for Ray Tracing"  http://www.cse.yorku.ca/~amana/research/grid.pdf
	ivec3 step = ivec3(sign(direction));
	vec3 t1 = (floor(startPosition) - startPosition)/direction;
	vec3 tDelta = 1/direction;
	vec3 t2 = t1 + tDelta;
	tDelta = abs(tDelta);
	vec3 tMax = max(t1, t2);
	if(direction.x == 0) tMax.x = 1.0/0.0;
	if(direction.y == 0) tMax.y = 1.0/0.0;
	if(direction.z == 0) tMax.z = 1.0/0.0;

	uvec3 voxelPosition = uvec3(floor(startPosition));
	int lastNormal = faceNormalIndex;
	uint block = getVoxel(voxelPosition);
	float total_tMax = 0;

	uvec3 sizeMask = upper - 1;

	while(block == 0) {
		if(tMax.x < tMax.y) {
			if(tMax.x < tMax.z) {
				voxelPosition.x += step.x;
				if((voxelPosition.x & sizeMask.x) != voxelPosition.x) {
					block = 0;
					break;
				}
				total_tMax = tMax.x;
				tMax.x += tDelta.x;
				lastNormal = 2 + (1 + int(step.x))/2;
			} else {
				voxelPosition.z += step.z;
				if((voxelPosition.z & sizeMask.z) != voxelPosition.z) {
					block = 0;
					break;
				}
				total_tMax = tMax.z;
				tMax.z += tDelta.z;
				lastNormal = 4 + (1 + int(step.z))/2;
			}
		} else {
			if(tMax.y < tMax.z) {
				voxelPosition.y += step.y;
				if((voxelPosition.y & sizeMask.y) != voxelPosition.y) {
					block = 0;
					break;
				}
				total_tMax = tMax.y;
				tMax.y += tDelta.y;
				lastNormal = 0 + (1 + int(step.y))/2;
			} else {
				voxelPosition.z += step.z;
				if((voxelPosition.z & sizeMask.z) != voxelPosition.z) {
					block = 0;
					break;
				}
				total_tMax = tMax.z;
				tMax.z += tDelta.z;
				lastNormal = 4 + (1 + int(step.z))/2;
			}
		}
		block = getVoxel(voxelPosition);
	}
	if(block == 0) discard;

	vec3 modifiedCameraSpacePos = cameraSpacePos*(1 + total_tMax*sizeScale*length(direction)/length(cameraSpacePos));
	vec4 projection = projectionMatrix*vec4(modifiedCameraSpacePos, 1);
	float depth = projection.z/projection.w;
	gl_FragDepth = ((gl_DepthRange.diff * depth) + gl_DepthRange.near + gl_DepthRange.far)/2.0;



	fragColor = decodeColor(block);
	fragColor.a = 1; // No transparency supported!
	fragColor = fragColor*vec4(ambientLight*normalVariations[lastNormal], 1);
}

void main() {
	if(textureIndex >= 0) {
		mainBlockDrop();
	} else {
		mainItemDrop();
	}
}
