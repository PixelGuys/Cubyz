#version 460

layout(location = 0) out vec4 frag_color;
layout(binding = 0) uniform sampler2D image;

layout(location = 0) in vec2 uv;
layout(location = 1) flat in vec4 fColor;

void main() {
	frag_color = texture(image, uv)*fColor;
	if(frag_color.a == 0) {
		discard;
	}
}
