#version 430

in vec3 vPos;
in vec3 vColor;

uniform mat4 mvp;

out vec3 color;

void main() {
	gl_Position = mvp*vec4(vPos, 1);

	color = vColor;
}
