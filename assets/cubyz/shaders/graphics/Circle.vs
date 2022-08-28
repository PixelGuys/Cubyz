#version 330 core

layout (location=0) in vec2 vertex_pos;

flat out vec4 color;
out vec2 unitPosition;


//in pixel
uniform vec2 center;
uniform float radius;
uniform vec2 screen;

uniform int circleColor;


void main() {

	// Convert to opengl coordinates:
	vec2 position_percentage = (center + vertex_pos*radius)/screen;
	
	vec2 position = vec2(position_percentage.x, -position_percentage.y)*2+vec2(-1, 1);
	
	gl_Position = vec4(position, 0, 1);
	
	color = vec4((circleColor & 0xff0000)>>16, (circleColor & 0xff00)>>8, circleColor & 0xff, (circleColor>>24) & 255)/255.0;
	
	unitPosition = vertex_pos;
}