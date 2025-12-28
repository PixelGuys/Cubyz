#version 460

layout(location = 0) in vec2 vertex_pos;

layout(location = 0) flat out vec4 color;

// in pixel
layout(location = 0) uniform vec2 start;
layout(location = 1) uniform vec2 direction;
layout(location = 2) uniform vec2 screen;

layout(location = 3) uniform int lineColor;

float srgbToLinear(float srgbChannel) {
	if(srgbChannel <= 0.04045) return srgbChannel/12.92;
	return pow((srgbChannel + 0.055)/1.055, 2.4);
}

vec3 srgbToLinear(vec3 srgb) {
	return vec3(
		srgbToLinear(srgb.r),
		srgbToLinear(srgb.g),
		srgbToLinear(srgb.b)
	);
}

void main() {
	// Convert to opengl coordinates:
	vec2 position_percentage = (start + vertex_pos*direction)/screen;

	vec2 position = vec2(position_percentage.x, -position_percentage.y)*2+vec2(-1, 1);

	gl_Position = vec4(position, 0, 1);

	color = vec4(srgbToLinear(vec3((lineColor & 0xff0000)>>16, (lineColor & 0xff00)>>8, lineColor & 0xff)/255.0), float((lineColor>>24) & 255)/255.0);
}
