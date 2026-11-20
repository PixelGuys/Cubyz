#version 460

layout(location = 0) out vec4 frag_color;

#ifdef OPEN_GL
layout(location = 5) uniform vec3 lineColor;
#else
layout(push_constant, std430) uniform _ {
	vec2 start;
	vec2 dimension;
	vec2 screen;
	int points;
	int offset;
	vec3 lineColor;
};
#endif

void main() {
	frag_color = vec4(lineColor, 1);
}
