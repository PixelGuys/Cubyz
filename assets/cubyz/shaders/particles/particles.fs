#version 430

in vec3 textureCoords;
flat in vec3 light;

uniform sampler2DArray textureSampler;
uniform sampler2DArray emissionTextureSampler;

layout(location = 0) out vec4 fragColor;

void main() {
	const vec4 texColor = texture(textureSampler, textureCoords);
	if(texColor.a != 1) {
		discard;
	}
	const vec3 pixelLight = max(light, texture(emissionTextureSampler, textureCoords).r*4);
	fragColor = texColor*vec4(pixelLight, 1);
}
