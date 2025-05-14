#version 460

layout(location = 0) in vec2 inTexCoords;

layout(location = 0) out vec2 texCoords;
layout(location = 1) flat out vec3[4] directions;

layout(location = 0) uniform mat4 invViewMatrix;
layout(location = 1) uniform vec2 tanXY;

void main() {
	directions[0] = (invViewMatrix * vec4(1*tanXY.x, 1, 1*tanXY.y, 0)).xyz;
	directions[1] = (invViewMatrix * vec4(1*tanXY.x, 1, -1*tanXY.y, 0)).xyz;
	directions[2] = (invViewMatrix * vec4(-1*tanXY.x, 1, 1*tanXY.y, 0)).xyz;
	directions[3] = (invViewMatrix * vec4(-1*tanXY.x, 1, -1*tanXY.y, 0)).xyz;
	texCoords = inTexCoords;
	vec2 position = inTexCoords*2 - vec2(1, 1);
	gl_Position = vec4(position, 0, 1);
}
