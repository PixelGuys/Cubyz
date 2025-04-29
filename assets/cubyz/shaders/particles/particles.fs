#version 430

flat in vec3 light;
in vec2 uv;
in float textureIndex;

uniform sampler2DArray textureSampler;
uniform sampler2DArray emissionTextureSampler;

layout(location = 0) out vec4 fragColor;

void main() {
    vec3 textureCoords = vec3(uv, textureIndex);
    vec4 texColor = texture(textureSampler, textureCoords);
    if(texColor.a != 1) {
        discard;
    }
    vec3 pixelLight = max(light, texture(emissionTextureSampler, textureCoords).r*4);
	fragColor = texColor*vec4(pixelLight, 1);
}