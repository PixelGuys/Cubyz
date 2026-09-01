#version 460

#include "frame_uniforms.glsl"

layout(location = 0) in vec3 worldPos;
layout(location = 1) flat in vec3 cloudMin;
layout(location = 2) flat in vec3 cloudSize;
layout(location = 3) flat in vec3 faceNormal;

layout(location = 0) out vec4 fragColor;

layout(location = 0) uniform vec3 ambientLight;
layout(location = 1) uniform vec4 cloudColor;
layout(location = 2) uniform vec2 screenSize;
layout(location = 3) uniform int skipDepthTests;
layout(binding = 4) uniform sampler2D sceneDepth;

#ifdef COLOR_PASS
struct Fog {
	vec3 color;
	float density;
	float fogLower;
	float fogHigher;
};
layout(location = 6) uniform Fog fog;
layout(binding = 5) uniform sampler2D cloudDepth;
#endif

int dominantAxis(vec3 values) {
	int axis = 0;
	if(values.y >= values.x) axis = 1;
	if(values.z >= max(values.x, values.y)) axis = 2;
	return axis;
}

#ifdef COLOR_PASS
float densityIntegral(float dist, float zStart, float zDist, float fogLower, float fogHigher) {
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

float calculateFogDistance(float dist, float zStart, float zScale, float fogDensity, float fogLower, float fogHigher) {
	float distCameraTerrain = densityIntegral(dist, zStart, zScale*dist, fogLower, fogHigher)*fogDensity;
	float distFromTerrain = -distCameraTerrain;
	if(distCameraTerrain < 10) {
		return distFromTerrain;
	} else if(distFromTerrain > -5 && dist != 0) {
		return distFromTerrain;
	} else {
		return -5;
	}
}

vec3 applyFrontfaceFog(float fogDistance, vec3 fogColor, vec3 inColor) {
	float fogFactor = exp(fogDistance);
	inColor *= fogFactor;
	inColor += fogColor;
	inColor -= fogColor*fogFactor;
	return inColor;
}
#endif

void main() {
	vec3 dir = worldPos;
	vec3 boxMax = cloudMin + cloudSize;
	vec3 t0 = cloudMin/dir;
	vec3 t1 = boxMax/dir;
	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);
	float tEnter = max(max(tmin.x, tmin.y), tmin.z);
	float tExit = min(min(tmax.x, tmax.y), tmax.z);
	if(tExit < 0.0 || tEnter > tExit) discard;

	vec3 hitNormal = vec3(0);
	if(tEnter > 0.0) {
		int axis = dominantAxis(tmin);
		hitNormal[axis] = dir[axis] > 0.0 ? -1.0 : 1.0;
	} else {
		int axis = dominantAxis(-tmax);
		hitNormal[axis] = dir[axis] > 0.0 ? 1.0 : -1.0;
	}
	if(dot(hitNormal, faceNormal) < 0.5) discard;

	if(skipDepthTests == 0) {
		vec2 uv = gl_FragCoord.xy/screenSize;
		if(gl_FragCoord.z > texture(sceneDepth, uv).r) discard;
#ifdef COLOR_PASS
		if(abs(gl_FragCoord.z - texture(cloudDepth, uv).r) > 0.0005) discard;
#endif
	}

#ifdef COLOR_PASS
	vec3 color = cloudColor.rgb*pow(max(ambientLight, vec3(0.001)), vec3(2.4));
	float dist = length(worldPos);
	float zScale = dist > 0.001 ? worldPos.z/dist : 0.0;
	float fogDistance = calculateFogDistance(dist, playerPositionFraction.z, zScale, fog.density, fog.fogLower - playerPositionInteger.z, fog.fogHigher - playerPositionInteger.z);
	color = applyFrontfaceFog(fogDistance, fog.color, color);
	fragColor = vec4(color, cloudColor.a);
#else
	fragColor = vec4(0);
#endif
}
