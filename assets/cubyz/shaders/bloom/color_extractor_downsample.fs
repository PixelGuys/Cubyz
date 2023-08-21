#version 430

layout(location=0) out vec4 fragColor;

in vec2 texCoords;

layout(binding = 3) uniform sampler2D color;

vec3 linearSample(ivec2 start) {
	vec3 outColor = vec3(0);
	outColor += texelFetch(color, start, 0).rgb;
	outColor += texelFetch(color, start + ivec2(0, 1), 0).rgb;
	outColor += texelFetch(color, start + ivec2(1, 0), 0).rgb;
	outColor += texelFetch(color, start + ivec2(1, 1), 0).rgb;
	return outColor*0.25;
}

void main() {
	vec3 bufferData = linearSample(ivec2(texCoords));
	float bloomFactor = max(max(bufferData.x, max(bufferData.y, bufferData.z)) - 1.0, 0);
	fragColor = vec4(bufferData*bloomFactor, 1);
}