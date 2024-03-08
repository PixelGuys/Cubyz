#version 430

in vec3 mvVertexPos;
in vec3 light;
flat in int blockType;
flat in int faceNormal;
flat in int isBackFace;
flat in int ditherSeed;
// For raymarching:
in vec3 startPosition;
in vec3 direction;

uniform sampler2DArray texture_sampler;
uniform sampler2DArray emissionSampler;
uniform sampler2DArray reflectivitySampler;
uniform samplerCube reflectionMap;
uniform float reflectionMapSize;

layout(location = 0) out vec4 fragColor;

struct TextureData {
	uint textureIndices[6];
	uint absorption;
	float fogDensity;
	uint fogColor;
};

layout(std430, binding = 1) buffer _textureData
{
	TextureData textureData[];
};


const float[6] normalVariations = float[6](
	1.0,
	0.84,
	0.92,
	0.92,
	0.96,
	0.88
);
const vec3[6] normals = vec3[6](
	vec3(0, 0, 1),
	vec3(0, 0, -1),
	vec3(1, 0, 0),
	vec3(-1, 0, 0),
	vec3(0, 1, 0),
	vec3(0, -1, 0)
);

float ditherThresholds[16] = float[16] (
	1/17.0, 9/17.0, 3/17.0, 11/17.0,
	13/17.0, 5/17.0, 15/17.0, 7/17.0,
	4/17.0, 12/17.0, 2/17.0, 10/17.0,
	16/17.0, 8/17.0, 14/17.0, 6/17.0
);

ivec2 random1to2(int v) {
	ivec4 fac = ivec4(11248723, 105436839, 45399083, 5412951);
	int seed = v.x*fac.x ^ fac.y;
	return seed*fac.zw;
}

bool passDitherTest(float alpha) {
	ivec2 screenPos = ivec2(gl_FragCoord.xy);
	screenPos += random1to2(ditherSeed);
	screenPos &= 3;
	return alpha > ditherThresholds[screenPos.x*4 + screenPos.y];
}

vec2 getTextureCoordsNormal(vec3 voxelPosition, int textureDir) {
	switch(textureDir) {
		case 0:
			return vec2(voxelPosition.x, voxelPosition.y);
		case 1:
			return vec2(15 - voxelPosition.x, voxelPosition.y);
		case 2:
			return vec2(voxelPosition.y, voxelPosition.z);
		case 3:
			return vec2(15 - voxelPosition.y, voxelPosition.z);
		case 4:
			return vec2(15 - voxelPosition.x, voxelPosition.z);
		case 5:
			return vec2(voxelPosition.x, voxelPosition.z);
	}
}

vec4 fixedCubeMapLookup(vec3 v) { // Taken from http://the-witness.net/news/2012/02/seamless-cube-map-filtering/
	float M = max(max(abs(v.x), abs(v.y)), abs(v.z));
	float scale = (reflectionMapSize - 1)/reflectionMapSize;
	if (abs(v.x) != M) v.x *= scale;
	if (abs(v.y) != M) v.y *= scale;
	if (abs(v.z) != M) v.z *= scale;
	return texture(reflectionMap, v);
}

void main() {
	uint textureIndex = textureData[blockType].textureIndices[faceNormal];
	float normalVariation = normalVariations[faceNormal];
	vec3 textureCoords = vec3(getTextureCoordsNormal(startPosition/16, faceNormal), textureIndex);
	float reflectivity = texture(reflectivitySampler, textureCoords).r;
	vec3 normal = normals[faceNormal];
	vec3 pixelLight = max(light*normalVariation, texture(emissionSampler, textureCoords).r*4);
	fragColor = texture(texture_sampler, textureCoords)*vec4(pixelLight, 1);
	fragColor.rgb += (reflectivity*fixedCubeMapLookup(reflect(direction, normal)).xyz)*pixelLight;

	if(!passDitherTest(fragColor.a)) discard;
	fragColor.a = 1;
}
