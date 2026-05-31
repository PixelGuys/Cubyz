#version 460

layout(location = 1) in vec3 direction;
layout(location = 2) in vec2 uv;
layout(location = 3) flat in vec3 normal;
layout(location = 4) flat in int textureIndex;
layout(location = 5) flat in int isBackFace;
layout(location = 7) flat in int opaqueInLod;

layout(location = 5) uniform float lodDistance;

layout(binding = 0) uniform sampler2DArray textureSampler;
layout(binding = 5) uniform sampler2D ditherTexture;

layout(std430, binding = 1) buffer _animatedTexture
{
	float animatedTexture[];
};

void main() {
	float animatedTextureIndex = animatedTexture[textureIndex];
	vec3 textureCoords = vec3(uv, animatedTextureIndex);
	vec4 color = texture(textureSampler, textureCoords);
	if (color.a < 0.5) discard;
}
