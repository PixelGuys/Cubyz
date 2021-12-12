#version 430

layout (location=0)  in vec3 position;
layout (location=1)  in vec2 texCoord;
layout (location=2)  in vec3 vertexNormal;

out vec2 outTexCoord;
out vec3 mvVertexPos;
out float outSelected;
out vec3 outLight;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 ambientLight;
uniform vec3 directionalLight;
uniform int light;

vec3 calcLight(int srgb) {
	float s = (srgb >> 24) & 255;
	float r = (srgb >> 16) & 255;
	float g = (srgb >> 8) & 255;
	float b = (srgb >> 0) & 255;
	s = s*(1 - dot(directionalLight, vertexNormal));
	r = max(s*ambientLight.x, r);
	g = max(s*ambientLight.y, g);
	b = max(s*ambientLight.z, b);
	return vec3(r, g, b)/255;
}

void main() {
	vec4 mvPos = viewMatrix * vec4(position, 1);
	gl_Position = projectionMatrix * mvPos;
    outTexCoord = texCoord;
    mvVertexPos = mvPos.xyz;
	outLight = calcLight(light);
}