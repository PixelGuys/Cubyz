#version 460

layout(location = 0) in vec4 vertex_pos;

layout(location = 0) flat out vec4 color;

// in pixel
layout(location = 0) uniform vec2 start;
layout(location = 1) uniform vec2 size;
layout(location = 2) uniform vec2 screen;
layout(location = 3) uniform float lineWidth;

layout(location = 4) uniform int rectColor;

void main() {
	// Convert to opengl coordinates:
	vec2 position_percentage = (start + vertex_pos.xy*size + vertex_pos.zw*lineWidth)/screen;

	vec2 position = vec2(position_percentage.x, -position_percentage.y)*2+vec2(-1, 1);

	gl_Position = vec4(position, 0, 1);

	color = vec4((rectColor & 0xff0000)>>16, (rectColor & 0xff00)>>8, rectColor & 0xff, (rectColor>>24) & 255)/255.0;;
}
