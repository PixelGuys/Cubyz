#version 430 core

//in pixel
uniform vec2 start;
uniform vec2 dimension;
uniform vec2 screen;
uniform int points;
uniform int offset;

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