#version 430
out vec4 fragColor;
  
in vec2 texCoords;

uniform sampler2D color;

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

void main() {
	fragColor = texture(color, texCoords);
	float densityAdjustment = sqrt(dot(tanXY*(texCoords*2 - 1), tanXY*(texCoords*2 - 1)) + 1);
	float fogDistance = calculateFogDistance(texelFetch(depthTexture, ivec2(gl_FragCoord.xy), 0).r, fog.density*densityAdjustment);
	vec3 fogColor = fog.color;
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
	fragColor.rgb /= fragColor.a;
	float maxColor = max(1.0, max(fragColor.r, max(fragColor.g, fragColor.b)));
	fragColor.rgb = fragColor.rgb/maxColor;
}