#version 430

in vec3 vPos;
in vec3 vColor;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat4 modelMatrix;

out vec3 color;

void main() {
	gl_Position = projectionMatrix*viewMatrix*modelMatrix*vec4(vPos, 1);

	color = vColor;
}
