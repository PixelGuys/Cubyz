#version 430

layout(location=0) out vec4 fragColor;

in vec2 texCoords;

layout(binding = 3) uniform sampler2D color;

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

vec3 fetch(ivec2 pos) {
	vec4 rgba = texelFetch(color, pos, 0);
	if(blockType != 0) { // TODO: Handle air fog as well.
		float fogDistance = calculateFogDistance(texelFetch(depthTexture, pos, 0).r);
		vec3 fogColor = unpackColor(textureData[blockType].fogColor);
		float fogFactor = exp(fogDistance);
		vec4 sourceColor = vec4(fogColor, 1);
		sourceColor.a = 1.0/fogFactor;
		sourceColor.rgb *= sourceColor.a;
		sourceColor.rgb -= fogColor;
		vec3 source2Color = vec3(1);
		rgba = vec4(
			source2Color*rgba.rgb + rgba.a*sourceColor.rgb,
			rgba.a*sourceColor.a
		);
	}
	if(rgba.a < 1) return vec3(0); // Prevent t-junctions from transparency from making a huge mess.
	return rgba.rgb/rgba.a;
}

vec3 linearSample(ivec2 start) {
	vec3 outColor = vec3(0);
	outColor += fetch(start);
	outColor += fetch(start + ivec2(0, 1));
	outColor += fetch(start + ivec2(1, 0));
	outColor += fetch(start + ivec2(1, 1));
	return outColor*0.25;
}

void main() {
	vec3 bufferData = linearSample(ivec2(texCoords));
	float bloomFactor = max(max(bufferData.x, max(bufferData.y, bufferData.z)) - 1.0, 0);
	fragColor = vec4(bufferData*bloomFactor, 1);
}