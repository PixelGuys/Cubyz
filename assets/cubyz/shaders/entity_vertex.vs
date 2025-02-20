#version 430

out vec2 outTexCoord;
out vec3 mvVertexPos;
out vec3 outLight;
flat out vec3 normal;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform vec3 ambientLight;
uniform vec3 directionalLight;
uniform int light;

struct QuadInfo {
	vec3 normal;
	vec3 corners[4];
	vec2 cornerUV[4];
	uint textureSlot;
	int opaqueInLod;
};

layout(std430, binding = 11) buffer _quads
{
	QuadInfo quads[];
};

vec3 calcLight(int srgb) {
	float s = (srgb >> 24) & 255;
	float r = (srgb >> 16) & 255;
	float g = (srgb >> 8) & 255;
	float b = (srgb >> 0) & 255;
	r = max(s*ambientLight.x, r);
	g = max(s*ambientLight.y, g);
	b = max(s*ambientLight.z, b);
	return vec3(r, g, b)/255;
}

void main() {
	int faceID = gl_VertexID >> 2;
	int vertexID = gl_VertexID & 3;

	normal = quads[faceID].normal;

	vec3 position = quads[faceID].corners[vertexID];

	vec4 mvPos = viewMatrix*vec4(position, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
	outTexCoord = quads[faceID].cornerUV[vertexID];
	outLight = calcLight(light);
}
