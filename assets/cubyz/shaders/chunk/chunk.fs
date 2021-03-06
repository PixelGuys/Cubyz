#version 330

in vec2 outTexCoord;
in vec3 lightColor;

out vec4 fragColor;

uniform sampler2D texture_sampler;
uniform int atlasSize;

vec4 getTextureColor() {
	return texture(texture_sampler, outTexCoord/atlasSize);
}

void main() {
	vec4 color = getTextureColor();
	if(color.a != 1)
		discard;
	fragColor = color*vec4(lightColor, 1);
}
