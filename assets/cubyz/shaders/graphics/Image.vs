#version 330 core

layout (location=0) in vec2 vertex_pos;

out vec2 uv;
flat out vec4 fColor;

//in pixel
uniform vec2 start;
uniform vec2 size;
uniform vec2 screen;

uniform int color;

void main() {

	// Convert to opengl coordinates:
	vec2 position_percentage = (start + vertex_pos*size)/screen;
	
	vec2 position = vec2(position_percentage.x, -position_percentage.y)*2+vec2(-1, 1);
	
	gl_Position = vec4(position, 0, 1);
	
	fColor = vec4((color & 0xff0000)>>16, (color & 0xff00)>>8, color & 0xff, (color>>24) & 255)/255.0;
	uv = vertex_pos;
}