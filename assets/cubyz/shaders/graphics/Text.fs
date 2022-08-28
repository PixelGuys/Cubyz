#version 330 

layout (location=0) out vec4 frag_color;

in vec2 frag_face_pos;
in vec4 color;

uniform sampler2D texture_sampler;

//in pxls
uniform vec4 texture_rect;
uniform vec2 fontSize;
uniform int fontEffects;

vec2 convert2Proportional(vec2 original, vec2 full){
	return vec2(original.x/full.x, original.y/full.y);
}


void main(){
	vec4 texture_rect_percentage =  vec4(convert2Proportional(texture_rect.xy, fontSize), convert2Proportional(texture_rect.zw, fontSize));
	vec2 texture_position = vec2(
				texture_rect_percentage.x+
				frag_face_pos.x*texture_rect_percentage.z
			,
				texture_rect_percentage.y+
				frag_face_pos.y*texture_rect_percentage.w
			);
	if ((fontEffects & 0x01000000) != 0) { // make it bold in y by sampling more pixels.
		vec2 pixel_offset = 1/fontSize;
		frag_color = color*max(texture(texture_sampler, texture_position),
					texture(texture_sampler, texture_position + vec2(0, 0.5f/fontSize.y)));
	} else {
		frag_color = color*texture(texture_sampler,
			texture_position);
	}
}