#version 460

// in pixel
layout(location = 0) uniform vec2 start;
layout(location = 1) uniform vec2 dimension;
layout(location = 2) uniform vec2 screen;
layout(location = 3) uniform int points;
layout(location = 4) uniform int offset;

layout(std430, binding = 5) buffer _data
{
	float data[];
};


void main() {
	float x = gl_VertexID;
	float y = -data[(gl_VertexID+offset)%points];
	// Convert to opengl coordinates:
	vec2 position_percentage = (start + dimension*vec2(x/points, y))/screen;

	vec2 position = vec2(position_percentage.x, -position_percentage.y)*2 + vec2(-1, 1);

	gl_Position = vec4(position, 0, 1);
}
