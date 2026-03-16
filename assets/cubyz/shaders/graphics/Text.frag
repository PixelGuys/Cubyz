#version 460

layout(location = 0) out vec4 frag_color;

layout(location = 0) in vec2 frag_face_pos;
layout(location = 1) flat in vec4 color;

layout(binding = 0) uniform sampler2D textureSampler;

// in pixels
layout(location = 0) uniform vec4 textureRect;
layout(location = 1) uniform vec2 scene;
layout(location = 2) uniform vec2 offset;
layout(location = 3) uniform float ratio;
layout(location = 4) uniform int fontEffects;
layout(location = 6) uniform vec2 fontSize;
layout(location = 7) uniform vec4 textureBounds;

vec2 convert2Proportional(vec2 original, vec2 full){
	return vec2(original.x/full.x, original.y/full.y);
}

float sampleIfInBounds(vec2 pos, vec2 minBounds, vec2 maxBounds) {
	if (any(lessThan(pos, minBounds))) return 0;
	if (any(greaterThanEqual(pos, maxBounds))) return 0;
	return texture(textureSampler, pos).r;
}

void main() {
	vec4 textureRectPercentage = vec4(convert2Proportional(textureRect.xy, fontSize), convert2Proportional(textureRect.zw, fontSize));
	vec2 texture_position = vec2(
				textureRectPercentage.x+
				frag_face_pos.x*textureRectPercentage.z
			,
				textureRectPercentage.y+
				frag_face_pos.y*textureRectPercentage.w
			);
	if ((fontEffects & 0x01000000) != 0) { // make it bold in y by sampling more pixels.
		vec2 pixel_offset = 1/fontSize;
		vec4 textureBoundsPercentage = vec4(convert2Proportional(textureBounds.xy, fontSize), convert2Proportional(textureBounds.zw, fontSize));
		vec2 minTextureCoord = textureBoundsPercentage.xy;
		vec2 maxTextureCoord = textureBoundsPercentage.xy + textureBoundsPercentage.zw;
		float textureValue = sampleIfInBounds(texture_position, minTextureCoord, maxTextureCoord);
		textureValue = max(textureValue, sampleIfInBounds(texture_position + vec2(0, 0.5f/fontSize.y), minTextureCoord, maxTextureCoord));
		textureValue = max(textureValue, sampleIfInBounds(texture_position + vec2(0.5f/fontSize.x, 0), minTextureCoord, maxTextureCoord));
		textureValue = max(textureValue, sampleIfInBounds(texture_position + 0.5f/fontSize.xy, minTextureCoord, maxTextureCoord));
		frag_color = color*textureValue;
	} else {
		frag_color = color*texture(textureSampler, texture_position).r;
	}
}
