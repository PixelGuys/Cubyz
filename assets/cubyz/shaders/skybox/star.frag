#version 460

layout(location = 0) in vec3 pos;
layout(location = 1) in flat vec3 centerPos;
layout(location = 2) in flat vec3 color;

layout(location = 0, index = 0) out vec4 fragColor;

void main() {
	if (dot(pos - centerPos, pos - centerPos) > 1.0/12.0)
		discard;

	fragColor = vec4(color, 1);
}
