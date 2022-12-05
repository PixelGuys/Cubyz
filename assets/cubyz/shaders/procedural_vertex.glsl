#version 330

layout (location=0) in vec2 vertex_pos;

out vec2 uv;

void main() {

	// Convert to opengl coordinates:
	vec2 position = vec2(vertex_pos.x, -vertex_pos.y)*2+vec2(-1, 1);
	
	gl_Position = vec4(position, 0, 1);
	
	uv = vertex_pos*vec2(1, -1) + vec2(0, 1);
}