#version 460

layout(location = 0) in vec2 inTexCoords;

layout(location = 0) out vec3 coords;

layout(location = 0) uniform float reflectionMapSize;

void main() {
	coords = vec3((inTexCoords*2 - vec2(1, 1))*(reflectionMapSize + 1)/reflectionMapSize, 1);
	gl_Position = vec4(inTexCoords*2 - vec2(1, 1), 0, 1);
}
