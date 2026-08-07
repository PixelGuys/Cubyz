#version 460

layout(location = 0) out vec4 frag_color;

layout(location = 0) in vec3 color;

void main() {
	frag_color = vec4(color, 1);
}
