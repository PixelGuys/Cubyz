layout (std140, binding = 0) uniform _frameData
{
	mat4 projectionMatrix;
	mat4 viewMatrix;
	mat4 lightProjectionMatrix;
	mat4 lightViewMatrix;
	ivec3 playerPositionInteger;
	vec3 playerPositionFraction;
};
