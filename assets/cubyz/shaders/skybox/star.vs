#version 430

in vec3 vPos;
in vec3 vColor;

struct star {
	vec4 pos;
	vec4 col;
};

layout (std430, binding = 12) buffer _starBuffer {
	star starData[];
};

uniform mat4 mvp;

out vec3 pos;
out vec3 starPos;
out vec3 color;

void main() {
	gl_Position = mvp*vec4(vPos, 1);

	pos = vPos;
	starPos = starData[gl_VertexID/3].pos.xyz;
	color = starData[gl_VertexID/3].col.xyz;
}
