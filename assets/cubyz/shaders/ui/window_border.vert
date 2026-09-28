#version 460

layout(location = 0) in vec2 vertex_pos;

layout(location = 0) flat out vec2 startCoord;
layout(location = 1) flat out vec2 endCoord;
layout(location = 2) flat out vec4 fColor;

#ifdef OPEN_GL
// in pixel
layout(location = 0) uniform vec2 start;
layout(location = 1) uniform vec2 size;
layout(location = 2) uniform vec2 screen;

layout(location = 3) uniform int color;
#else
layout(push_constant, std430) uniform _ {
	vec2 start;
	vec2 size;
	vec2 screen;
	int color;
	float scale;
	vec2 effectLength;
};
#endif

void main() {
	// Convert to opengl coordinates:
	vec2 position_percentage = (start + vertex_pos*size)/screen;
	startCoord.x = start.x;
	startCoord.y = screen.y - start.y - size.y;
	endCoord.x = start.x + size.x;
	endCoord.y = screen.y - start.y;

	vec2 position = vec2(position_percentage.x, -position_percentage.y)*2+vec2(-1, 1);

	gl_Position = vec4(position, 0, 1);

	fColor = vec4((color & 0xff0000)>>16, (color & 0xff00)>>8, color & 0xff, (color>>24) & 255)/255.0;
}
