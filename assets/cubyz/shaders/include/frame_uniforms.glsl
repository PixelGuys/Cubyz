layout (std140, binding = 0) uniform _frameData
{
	mat4 projectionMatrix;
	mat4 viewMatrix;
	ivec3 playerPositionInteger;
	vec3 playerPositionFraction;
	mat4 lightProjectionMatrix;
	mat4 lightViewMatrix;
	bool isDepth;
};
