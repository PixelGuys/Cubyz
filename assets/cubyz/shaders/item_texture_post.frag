#version 460

layout(location = 0) out vec4 fragColor;

layout(location = 0) in vec2 texCoords;

layout(binding = 3) uniform sampler2D color;

#ifdef OPEN_GL
layout(location = 0) uniform bool transparent;
#else
layout(push_constant, std430) uniform _ {
	bool transparent;
};
#endif

void main() {
	fragColor = texture(color, texCoords);
	if(transparent) {
		fragColor.a = 1;
		// TODO: Remove the background color. Somehow?
	}
	float maxColor = max(1.0, max(fragColor.r, max(fragColor.g, fragColor.b)));
	fragColor.rgb = fragColor.rgb/maxColor;
}
