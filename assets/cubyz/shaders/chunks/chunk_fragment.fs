#version 430

in vec3 mvVertexPos;
flat in int blockType;
flat in int faceNormal;
flat in int modelIndex;
flat in int isBackFace;
flat in int ditherSeed;
// For raymarching:
flat in ivec3 minPos;
flat in ivec3 maxPos;
in vec3 startPosition;
in vec3 direction;

uniform vec3 ambientLight;
uniform sampler2DArray texture_sampler;
uniform sampler2DArray emissionSampler;

layout(location = 0) out vec4 fragColor;

struct TextureData {
	int textureIndices[6];
	uint absorption;
	float reflectivity;
	float fogDensity;
	uint fogColor;
};

layout(std430, binding = 1) buffer _textureData
{
	TextureData textureData[];
};


const float[6] normalVariations = float[6](
	1.0, //vec3(0, 1, 0),
	0.84, //vec3(0, -1, 0),
	0.92, //vec3(1, 0, 0),
	0.92, //vec3(-1, 0, 0),
	0.96, //vec3(0, 0, 1),
	0.88 //vec3(0, 0, -1)
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
			return vec2(15 - voxelPosition.x, voxelPosition.z);
		case 1:
			return vec2(voxelPosition.x, voxelPosition.z);
		case 2:
			return vec2(15 - voxelPosition.z, voxelPosition.y);
		case 3:
			return vec2(voxelPosition.z, voxelPosition.y);
		case 4:
			return vec2(voxelPosition.x, voxelPosition.y);
		case 5:
			return vec2(15 - voxelPosition.x, voxelPosition.y);
	}
}

void main() {
	int textureIndex = textureData[blockType].textureIndices[faceNormal];
	float normalVariation = normalVariations[faceNormal];
	vec3 textureCoords = vec3(getTextureCoordsNormal(startPosition/16, faceNormal), textureIndex);
	fragColor = texture(texture_sampler, textureCoords)*vec4(ambientLight*normalVariation, 1);

	if(!passDitherTest(fragColor.a)) discard;
	fragColor.a = 1;

	fragColor.rgb += texture(emissionSampler, textureCoords).rgb;
}
