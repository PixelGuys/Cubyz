#ifdef OPEN_GL
layout (std140, binding = 0) uniform _frameData
#else
layout (std140, binding = 0, set = 1) uniform _frameData
#endif
{
	mat4 projectionMatrix;
	mat4 viewMatrix;
	ivec3 playerPositionInteger;
	vec3 playerPositionFraction;
};
