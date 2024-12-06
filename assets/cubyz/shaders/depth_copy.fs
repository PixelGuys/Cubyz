#version 430
out vec4 fragColor;
in vec2 texCoords;

uniform float zNear;
uniform float zFar;

layout(binding = 5) uniform sampler2D depthBuffer;

float zFromDepth(float depthBufferValue) {
	return zNear*zFar/(depthBufferValue*(zNear - zFar) + zFar);
}

void main() {
	fragColor.r = zFromDepth(texture(depthBuffer, texCoords).r);
}