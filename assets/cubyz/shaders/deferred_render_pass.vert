#version 460

layout(location = 0) in vec2 inTexCoords;

layout(location = 0) out vec2 texCoords;
layout(location = 1) flat out vec3[4] directions;

#ifdef OPEN_GL
layout(location = 0) uniform mat4 invViewMatrix;
layout(location = 1) uniform vec2 tanXY;
#else
layout(push_constant, std430) uniform _ {
	mat4 invViewMatrix;
	vec2 tanXY;
	float zNear;
	float zFar;
};
#endif

void main() {
#ifdef OPEN_GL
	texCoords = vec2(inTexCoords.x, 1 - inTexCoords.y);
	directions[0] = (invViewMatrix * vec4(1*tanXY.x, 1, 1*tanXY.y, 0)).xyz;
	directions[1] = (invViewMatrix * vec4(1*tanXY.x, 1, -1*tanXY.y, 0)).xyz;
	directions[2] = (invViewMatrix * vec4(-1*tanXY.x, 1, 1*tanXY.y, 0)).xyz;
	directions[3] = (invViewMatrix * vec4(-1*tanXY.x, 1, -1*tanXY.y, 0)).xyz;
#else
	texCoords = inTexCoords;
	directions[0] = (invViewMatrix * vec4(1*tanXY.x, 1, -1*tanXY.y, 0)).xyz;
	directions[1] = (invViewMatrix * vec4(1*tanXY.x, 1, 1*tanXY.y, 0)).xyz;
	directions[2] = (invViewMatrix * vec4(-1*tanXY.x, 1, -1*tanXY.y, 0)).xyz;
	directions[3] = (invViewMatrix * vec4(-1*tanXY.x, 1, 1*tanXY.y, 0)).xyz;
#endif
	gl_Position = vec4(inTexCoords*2 + vec2(-1, -1), 0, 1);
}
