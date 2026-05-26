#version 460

layout(location = 0) in vec3 mvVertexPos;
layout(location = 1) in vec3 direction;
layout(location = 2) in vec2 uv;
layout(location = 3) flat in vec3 normal;
layout(location = 4) flat in int isBackFace;
layout(location = 5) flat in float distanceForLodCheck;
layout(location = 6) flat in int opaqueInLod;

layout(location = 5) uniform float lodDistance;

layout(std430, binding = 1) buffer _animatedTexture
{
	float animatedTexture[];
};

void main() {
}
