#version 430

struct star {
	vec4 poses[3];

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
out flat vec3 starPos;
out flat vec3 color;

void main() {
	gl_Position = mvp*vec4(starData[gl_VertexID/3].poses[gl_VertexID%3].xyz, 1);

	pos = starData[gl_VertexID/3].poses[gl_VertexID%3].xyz;
	starPos = starData[gl_VertexID/3].pos;
	color = starData[gl_VertexID/3].col * starOpacity;
}
