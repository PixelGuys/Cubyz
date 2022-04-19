#version 430

layout(location=0) out vec4 fragColor;

in vec2 texCoords;

layout(location = 0, binding = 3) uniform sampler2D color;

void main() {
	vec3 bufferData = texture(color, texCoords).rgb;
	float bloomFactor = min(max(max(bufferData.x, max(bufferData.y, bufferData.z)) - 251.0/1023.0, 0)*1023.0/4.0, 0.5);
	fragColor = vec4(bufferData*bloomFactor, 1);
}