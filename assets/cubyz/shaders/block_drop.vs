#version 430

layout (location=0)  in vec3 position;
layout (location=1)  in vec2 texCoord;
layout (location=2)  in vec3 vertexNormal;

out vec3 outTexCoord;
out vec3 mvVertexPos;
out float outSelected;
out vec3 outLight;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;

uniform int light;
uniform vec3 ambientLight;
uniform vec3 directionalLight;

uniform int texPosX;
uniform int texNegX;
uniform int texPosY;
uniform int texNegY;
uniform int texPosZ;
uniform int texNegZ;

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

void main()
{
	vec4 mvPos = viewMatrix * vec4(position, 1);
	gl_Position = projectionMatrix * mvPos;
	int texture = 0;
	if (vertexNormal == vec3(1, 0, 0)) {
		texture = texPosX;
	} else if (vertexNormal == vec3(-1, 0, 0)) {
		texture = texNegX;
	} else if (vertexNormal == vec3(0, 1, 0)) {
		texture = texPosY;
	} else if (vertexNormal == vec3(0, -1, 0)) {
		texture = texNegY;
	} else if (vertexNormal == vec3(0, 0, 1)) {
		texture = texPosZ;
	} else if (vertexNormal == vec3(0, 0, -1)) {
		texture = texNegZ;
	} else {
		texture = texNegX;
	}
	outLight = calcLight(light)/255;
    outTexCoord = vec3(texCoord, float(texture));
    mvVertexPos = mvPos.xyz;
}