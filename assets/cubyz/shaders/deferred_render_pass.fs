#version 430
out vec4 fragColor;
in vec2 texCoords;
in vec3 direction;

uniform sampler2D color;

uniform sampler2D depthTexture;
uniform float zNear;
uniform float zFar;
uniform vec2 tanXY;

layout(binding = 5) uniform sampler2D bloomColor;

struct Fog {
	vec3 color;
	float density;
	float fogLower;
	float fogHigher;
};

uniform Fog fog;

uniform ivec3 playerPositionInteger;
uniform vec3 playerPositionFraction;

float zFromDepth(float depthBufferValue) {
	return zNear*zFar/(depthBufferValue*(zNear - zFar) + zFar);
}

float densityIntegral(float dist, float zStart, float zDist, float fogLower, float fogHigher) {
	// The density is constant until fogLower, then gets smaller linearly until reaching fogHigher, past which there is no fog.
	if(zDist < 0) {
		zStart += zDist;
		zDist = -zDist;
	}
	if(abs(zDist) < 0.001) {
		zDist = 0.001;
	}
	float beginLower = min(fogLower, zStart);
	float endLower = min(fogLower, zStart + zDist);
	float beginMid = max(fogLower, min(fogHigher, zStart));
	float endMid = max(fogLower, min(fogHigher, zStart + zDist));
	float midIntegral = -0.5*(endMid - fogHigher)*(endMid - fogHigher)/(fogHigher - fogLower) - -0.5*(beginMid - fogHigher)*(beginMid - fogHigher)/(fogHigher - fogLower);
	if(fogHigher == fogLower) midIntegral = 0;

	return (endLower - beginLower + midIntegral)/zDist*dist;
}

float calculateFogDistance(float dist, float densityAdjustment, float zStart, float zScale, float fogDensity, float fogLower, float fogHigher) {
	float distCameraTerrain = densityIntegral(dist*densityAdjustment, zStart, zScale*dist*densityAdjustment, fogLower, fogHigher)*fogDensity;
	float distFromCamera = 0;
	float distFromTerrain = distFromCamera - distCameraTerrain;
	if(distCameraTerrain < 10) { // Resolution range is sufficient.
		return distFromTerrain;
	} else {
		// Here we have a few options to deal with this. We could for example weaken the fog effect to fit the entire range.
		// I decided to keep the fog strength close to the camera and far away, with a fog-free region in between.
		// I decided to this because I want far away fog to work (e.g. a distant ocean) as well as close fog(e.g. the top surface of the water when the player is under it)
		if(distFromTerrain > -5 && dist != 0) {
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
	float dist = zFromDepth(texture(depthTexture, texCoords).r);
	float fogDistance = calculateFogDistance(dist, densityAdjustment, playerPositionInteger.z + playerPositionFraction.z, normalize(direction).z, fog.density, fog.fogLower, fog.fogHigher);
	fragColor.rgb = applyFrontfaceFog(fogDistance, fog.color, fragColor.rgb);
	float maxColor = max(1.0, max(fragColor.r, max(fragColor.g, fragColor.b)));
	fragColor.rgb = fragColor.rgb/maxColor;
}
