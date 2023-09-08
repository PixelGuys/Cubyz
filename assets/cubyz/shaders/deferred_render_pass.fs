#version 430
out vec4 fragColor;
  
in vec2 texCoords;

uniform sampler2D color;

uniform sampler2D depthTexture;
uniform int blockType;
uniform float nearPlane;

struct TextureData {
	int textureIndices[6];
	uint absorption;
	float reflectivity;
	float fogStrength;
	uint fogColor;
};

layout(std430, binding = 1) buffer _textureData
{
	TextureData textureData[];
};

vec3 unpackColor(uint color) {
	return vec3(
		color>>16 & 255u,
		color>>8 & 255u,
		color & 255u
	)/255.0;
}

float calculateFogDistance(float depthBufferValue) {
	float fogStrength = textureData[blockType].fogStrength;
	float distCameraTerrain = nearPlane*fogStrength/depthBufferValue;
	float distFromCamera = 0;
	float distFromTerrain = distFromCamera - distCameraTerrain;
	if(distCameraTerrain < 10) { // Resolution range is sufficient.
		return distFromTerrain;
	} else {
		// Here we have a few options to deal with this. We could for example weaken the fog effect to fit the entire range.
		// I decided to keep the fog strength close to the camera and far away, with a fog-free region in between.
		// I decided to this because I want far away fog to work (e.g. a distant ocean) as well as close fog(e.g. the top surface of the water when the player is under it)
		if(distFromTerrain > -5 && depthBufferValue != 0) {
			return distFromTerrain;
		} else if(distFromCamera < 5) {
			return distFromCamera - 10;
		} else {
			return -5;
		}
	}
}

void main() {
	fragColor = texture(color, texCoords);
	if(blockType != 0) { // TODO: Handle air fog as well.
		float fogDistance = calculateFogDistance(texelFetch(depthTexture, ivec2(gl_FragCoord.xy), 0).r);
		vec3 fogColor = unpackColor(textureData[blockType].fogColor);
		float fogFactor = exp(fogDistance);
		vec4 sourceColor = vec4(fogColor, 1);
		sourceColor.a = 1.0/fogFactor;
		sourceColor.rgb *= sourceColor.a;
		sourceColor.rgb -= fogColor;
		vec3 source2Color = vec3(1);
		fragColor = vec4(
			source2Color*fragColor.rgb + fragColor.a*sourceColor.rgb,
			fragColor.a*sourceColor.a
		);
	}
	fragColor.rgb /= fragColor.a;
	float maxColor = max(1.0, max(fragColor.r, max(fragColor.g, fragColor.b)));
	fragColor.rgb = fragColor.rgb/maxColor;
}