#version 460

layout(location = 0) in vec2 vertex_pos;

layout(location = 0) out vec2 uv;
layout(location = 1) flat out vec4 fColor;

// in pixel
layout(location = 0) uniform vec2 start;
layout(location = 1) uniform vec2 size;
layout(location = 2) uniform vec2 screen;
layout(location = 3) uniform vec2 uvOffset;
layout(location = 4) uniform vec2 uvDim;

layout(location = 5) uniform int color;

void main() {
	// Convert to opengl coordinates:
	vec2 position_percentage = (start + vec2(vertex_pos.x*size.x, size.y - vertex_pos.y*size.y))/screen;

	vec2 position = vec2(position_percentage.x, -position_percentage.y)*2+vec2(-1, 1);

	gl_Position = vec4(position, 0, 1);

	fColor = vec4((color & 0xff0000)>>16, (color & 0xff00)>>8, color & 0xff, (color>>24) & 255)/255.0;
	uv = uvOffset + vertex_pos*uvDim;
}
