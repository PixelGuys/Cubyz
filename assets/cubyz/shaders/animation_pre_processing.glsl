#version 430

layout (local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

struct AnimationData {
	uint startFrame;
	uint frames;
	uint time;
};

layout(std430, binding = 0) buffer _animation
{
	AnimationData animation[];
};
layout(std430, binding = 1) buffer _animatedTexture
{
	float animatedTexture[];
};

uniform uint time;
uniform uint size;

void main() {
	uint textureIndex = gl_GlobalInvocationID.x;
	if(textureIndex >= size) return;
	animatedTexture[textureIndex] = animation[textureIndex].startFrame + time / animation[textureIndex].time % animation[textureIndex].frames;
}
