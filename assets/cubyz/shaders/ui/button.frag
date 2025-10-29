#version 460

layout(location = 0) out vec4 frag_color;

layout(location = 0) in vec2 startCoord;
layout(location = 1) flat in vec4 fColor;

layout(binding = 0) uniform sampler2D image;

layout(location = 4) uniform float scale;

void main() {
	frag_color = texture(image, (gl_FragCoord.xy - startCoord)/(2*scale)/textureSize(image, 0));
	frag_color.a *= fColor.a;
	frag_color.rgb += fColor.rgb;
}
