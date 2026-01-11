#version 460

layout(location = 0) in vec2 vertex_pos;

layout(location = 0) out vec2 unitPosition;
layout(location = 1) flat out vec4 color;

// in pixel
layout(location = 0) uniform vec2 center;
layout(location = 1) uniform float radius;
layout(location = 2) uniform vec2 screen;

layout(location = 3) uniform int circleColor;

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
	vec2 position_percentage = (center + vertex_pos*radius)/screen;

	vec2 position = vec2(position_percentage.x, -position_percentage.y)*2+vec2(-1, 1);

	gl_Position = vec4(position, 0, 1);

	color = vec4(srgbToLinear(vec3((circleColor & 0xff0000)>>16, (circleColor & 0xff00)>>8, circleColor & 0xff)/255.0), float((circleColor>>24) & 255)/255.0);

	unitPosition = vertex_pos;
}
