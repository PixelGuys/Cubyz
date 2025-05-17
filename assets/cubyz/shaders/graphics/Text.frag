#version 460

layout(location = 0) out vec4 frag_color;

layout(location = 0) in vec2 frag_face_pos;
layout(location = 1) flat in vec4 color;

layout(binding = 0) uniform sampler2D textureSampler;

// in pixels
layout(location = 0) uniform vec4 texture_rect;
layout(location = 1) uniform vec2 scene;
layout(location = 2) uniform vec2 offset;
layout(location = 3) uniform float ratio;
layout(location = 4) uniform int fontEffects;
layout(location = 6) uniform vec2 fontSize;

vec2 convert2Proportional(vec2 original, vec2 full){
	return vec2(original.x/full.x, original.y/full.y);
}

void main() {
	vec4 texture_rect_percentage = vec4(convert2Proportional(texture_rect.xy, fontSize), convert2Proportional(texture_rect.zw, fontSize));
	vec2 texture_position = vec2(
				texture_rect_percentage.x+
				frag_face_pos.x*texture_rect_percentage.z
			,
				texture_rect_percentage.y+
				frag_face_pos.y*texture_rect_percentage.w
			);
	if ((fontEffects & 0x01000000) != 0) { // make it bold in y by sampling more pixels.
		vec2 pixel_offset = 1/fontSize;
		frag_color = color*max(texture(textureSampler, texture_position).r,
					texture(textureSampler, texture_position + vec2(0, 0.5f/fontSize.y)).r);
	} else {
		frag_color = color*texture(textureSampler,
			texture_position).r;
	}
}
