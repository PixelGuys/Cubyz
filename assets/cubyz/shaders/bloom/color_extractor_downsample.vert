#version 460

layout(location = 0) in vec2 inTexCoords;

layout(location = 0) out vec2 texCoords;
layout(location = 1) out vec2 normalizedTexCoords;
layout(location = 2) out vec3 direction;

layout(binding = 3) uniform sampler2D color;

layout(location = 0) uniform mat4 invViewMatrix;
layout(location = 1) uniform vec2 tanXY;

void main() {
	vec2 position = inTexCoords*2 - vec2(1, 1);
	direction = (invViewMatrix * vec4(position.x*tanXY.x, 1, position.y*tanXY.y, 0)).xyz;
	normalizedTexCoords = inTexCoords;
	texCoords = inTexCoords*textureSize(color, 0) - 0.25;
	gl_Position = vec4(position, 0, 1);
}
