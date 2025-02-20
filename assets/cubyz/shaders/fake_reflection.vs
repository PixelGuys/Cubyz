#version 430

layout (location=0)  in vec2 inTexCoords;

out vec3 coords;

uniform float reflectionMapSize;

void main() {
	coords = vec3((inTexCoords*2 - vec2(1, 1))*(reflectionMapSize + 1)/reflectionMapSize, 1);
	gl_Position = vec4(inTexCoords*2 - vec2(1, 1), 0, 1);
}
