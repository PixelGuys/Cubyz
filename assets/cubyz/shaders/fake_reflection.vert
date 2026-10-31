#version 460

layout(location = 0) in vec2 inTexCoords;

layout(location = 0) out vec3 coords;

layout(location = 0) uniform float reflectionMapSize;

void main() {
#ifdef OPEN_GL
	vec2 texCoords = vec2(inTexCoords.x, 1 - inTexCoords.y);
	coords = vec3((texCoords*2 + vec2(-1, -1))*(reflectionMapSize + 1)/reflectionMapSize, 1);
#else
	coords = vec3((inTexCoords*2 + vec2(-1, -1))*(reflectionMapSize + 1)/reflectionMapSize, 1);
#endif
	gl_Position = vec4(inTexCoords*2 + vec2(-1, -1), 0, 1);
}
