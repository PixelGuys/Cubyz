#version 460

layout(location = 0) in vec2 face_pos;

layout(location = 0) out vec2 frag_face_pos;
layout(location = 1) flat out vec4 color;

// in pixels
layout(location = 0) uniform vec4 texture_rect;
layout(location = 1) uniform vec2 scene;
layout(location = 2) uniform vec2 offset;
layout(location = 3) uniform float ratio;
layout(location = 4) uniform int fontEffects;

layout(location = 5) uniform float alpha;

vec2 convert2Proportional(vec2 original, vec2 full) {
	return vec2(original.x/full.x, original.y/full.y);
}

void main() {
	vec2 vertex_pos = face_pos*vec2(1, -1);
	vec2 position_percentage 	= convert2Proportional(floor(offset), scene);
	vec2 size_percentage		= convert2Proportional(floor(vec2(texture_rect.z, texture_rect.w)*ratio), scene);
	if ((fontEffects & 0x02000000) != 0) { // italic
		vertex_pos.x += vertex_pos.y/texture_rect.z;
	}

	// convert glyph coords to opengl coords
	vec4 rect = vec4(position_percentage, size_percentage);

	vec2 position = vec2(rect.x+vertex_pos.x*rect.z, -rect.y+vertex_pos.y*rect.w)*2+vec2(-1, 1);

	gl_Position = vec4(position, 0, 1);
	frag_face_pos = face_pos;
	color = vec4(vec3((fontEffects & 0xff0000)>>16, (fontEffects & 0xff00)>>8, fontEffects & 0xff)/255.0, alpha);
}
