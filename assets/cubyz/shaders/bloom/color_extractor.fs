#version 430

layout(location=0) out vec4 fragColor;

in vec2 texCoords;

layout(binding = 3) uniform sampler2D color;

void main() {
	vec3 bufferData = texture(color, texCoords).rgb;
	float bloomFactor = max(max(bufferData.x, max(bufferData.y, bufferData.z))*4 - 1.0, 0);
	fragColor = vec4(bufferData*bloomFactor, 1);
}