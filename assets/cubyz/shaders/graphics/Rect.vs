#version 330 core

layout (location=0) in vec2 vertex_pos;

flat out vec4 color;


//in pixel
uniform vec2 start;
uniform vec2 size;
uniform vec2 screen;

uniform int rectColor;


void main() {

	// Convert to opengl coordinates:
	vec2 position_percentage = (start + vertex_pos*size)/screen;
	
	vec2 position = vec2(position_percentage.x, -position_percentage.y)*2+vec2(-1, 1);
	
	gl_Position = vec4(position, 0, 1);
	
	color = vec4((rectColor & 0xff0000)>>16, (rectColor & 0xff00)>>8, rectColor & 0xff, (rectColor>>24) & 255)/255.0;;
}