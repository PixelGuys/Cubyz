#version 430

in vec3 vPos;

struct star {
	vec3 pos;
	float pad1;
	vec3 col;
	float pad2;
};

layout (std430, binding = 12) buffer _starBuffer {
	star starData[];
};

uniform mat4 mvp;
uniform float starOpacity;

out vec3 pos;
out vec3 starPos;
out vec3 color;

void main() {
	gl_Position = mvp*vec4(vPos, 1);

	pos = vPos;
	starPos = starData[gl_VertexID/3].pos.xyz;
	color = starData[gl_VertexID/3].col.xyz * starOpacity;
}
