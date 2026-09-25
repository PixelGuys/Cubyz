#version 460

layout(location = 0) out vec4 frag_color;

layout(location = 0) in vec2 startCoord;
layout(location = 1) flat in vec4 fColor;

layout(binding = 0) uniform sampler2D image;

#ifdef OPEN_GL
layout(location = 4) uniform float scale;
#else
layout(push_constant, std430) uniform _ {
	vec2 start;
	vec2 size;
	vec2 screen;
	int color;
	float scale;
};
#endif

void main() {
	frag_color = texture(image, (gl_FragCoord.xy - startCoord)/(2*scale)/textureSize(image, 0));
	frag_color *= fColor;
}
