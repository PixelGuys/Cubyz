#version 430
out vec4 fragColor;
in vec2 texCoords;

uniform sampler2D color;

uniform sampler2D depthTexture;
uniform float zNear;
uniform float zFar;
uniform vec2 tanXY;

layout(binding = 5) uniform sampler2D bloomColor;

struct Fog {
	vec3 color;
	float density;
};

uniform Fog fog;

float zFromDepth(float depthBufferValue) {
	return zNear*zFar/(depthBufferValue*(zNear - zFar) + zFar);
}

float calculateFogDistance(float depthBufferValue, float fogDensity) {
	float distCameraTerrain = zFromDepth(depthBufferValue)*fogDensity;
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

vec3 applyFrontfaceFog(float fogDistance, vec3 fogColor, vec3 inColor) {
	float fogFactor = exp(fogDistance);
	inColor *= fogFactor;
	inColor += fogColor;
	inColor -= fogColor*fogFactor;
	return inColor;
}

void main() {
	fragColor = texture(color, texCoords);
	fragColor += texture(bloomColor, texCoords);
	float densityAdjustment = sqrt(dot(tanXY*(texCoords*2 - 1), tanXY*(texCoords*2 - 1)) + 1);
	float fogDistance = calculateFogDistance(texture(depthTexture, texCoords).r, fog.density*densityAdjustment);
	fragColor.rgb = applyFrontfaceFog(fogDistance, fog.color, fragColor.rgb);
	float maxColor = max(1.0, max(fragColor.r, max(fragColor.g, fragColor.b)));
	fragColor.rgb = fragColor.rgb/maxColor;
}