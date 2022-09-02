#version 430

layout (location=0)  in vec3 position;
layout (location=1)  in vec3 texCoord;
layout (location=2)  in vec3 vertexNormal;
layout (location=3)  in int easyLight;

out vec2 outTexCoord;
flat out float textureIndex;
out vec3 mvVertexPos;
out vec3 outColor;

uniform mat4 projectionMatrix;
uniform vec3 ambientLight;
uniform vec3 directionalLight;
uniform mat4 viewMatrix;
uniform vec3 modelPosition;

layout(std430, binding = 0) buffer _animationTimes
{
    int animationTimes[];
};
layout(std430, binding = 1) buffer _animationFrames
{
    int animationFrames[];
};

uniform int time;

vec3 calcLight(int srgb) {
	float s = (srgb >> 24) & 255;
	float r = (srgb >> 16) & 255;
	float g = (srgb >> 8) & 255;
	float b = (srgb >> 0) & 255;
	s = s*(1 - dot(directionalLight, vertexNormal));
	r = max(s*ambientLight.x, r);
	g = max(s*ambientLight.y, g);
	b = max(s*ambientLight.z, b);
	return vec3(r, g, b);
}

void main() {
	outColor = calcLight(easyLight)*0.003890625;
	vec4 mvPos = viewMatrix*vec4(position + modelPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	outTexCoord = texCoord.xy;
	textureIndex = texCoord.z + time / animationTimes[int(texCoord.z)] % animationFrames[int(texCoord.z)];
	mvVertexPos = mvPos.xyz;
}
