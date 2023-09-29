#version 430

layout(location=0) out vec4 fragColor;

in vec2 texCoords;
in vec2 normalizedTexCoords;

layout(binding = 3) uniform sampler2D color;

uniform sampler2D depthTexture;
uniform float zNear;
uniform float zFar;
uniform vec2 tanXY;

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

vec3 fetch(ivec2 pos) {
	vec4 rgba = texelFetch(color, pos, 0);
	float densityAdjustment = sqrt(dot(tanXY*(normalizedTexCoords*2 - 1), tanXY*(normalizedTexCoords*2 - 1)) + 1);
	float fogDistance = calculateFogDistance(texelFetch(depthTexture, pos, 0).r, fog.density*densityAdjustment);
	vec3 fogColor = fog.color;
	rgba.rgb = applyFrontfaceFog(fogDistance, fog.color, rgba.rgb);
	return rgba.rgb/rgba.a;
}

vec3 linearSample(ivec2 start) {
	vec3 outColor = vec3(0);
	outColor += fetch(start);
	outColor += fetch(start + ivec2(0, 2));
	outColor += fetch(start + ivec2(2, 0));
	outColor += fetch(start + ivec2(2, 2));
	return outColor*0.25;
}

void main() {
	vec3 bufferData = linearSample(ivec2(texCoords));
	float bloomFactor = max(max(bufferData.x, max(bufferData.y, bufferData.z)) - 1.0, 0);
	fragColor = vec4(bufferData*bloomFactor, 1);
}