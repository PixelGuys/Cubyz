#version 330 core

layout (location=0) in vec2 vertex_pos;

out vec2 uv;

//in pixel
uniform vec2 start;
uniform vec2 size;
uniform vec2 screen;


void main() {

	// Convert to opengl coordinates:
	vec2 position_percentage = (start + vertex_pos*size)/screen;
	
	vec2 position = vec2(position_percentage.x, -position_percentage.y)*2+vec2(-1, 1);
	
	gl_Position = vec4(position, 0, 1);
	
	uv = vertex_pos;
}