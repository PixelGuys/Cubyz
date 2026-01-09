#version 430

layout(location = 0) out vec4 fragColor;

layout(location = 0) in vec3 textureCoords;
layout(location = 1) flat in vec3 light;
layout(location = 2) flat in float alpha;

layout(binding = 0) uniform sampler2DArray textureSampler;
layout(binding = 1) uniform sampler2DArray emissionTextureSampler;


float interleavedGradientNoise(ivec2 screenPos)
{
    return fract(52.9829189f * fract(0.06711056f*float(screenPos.x) + 0.00583715f*float(screenPos.y)));
}

bool passDitherTest(float alpha) {
	ivec2 screenPos = ivec2(gl_FragCoord.xy);
	return alpha > interleavedGradientNoise(screenPos);
}

void main() {
	const vec4 texColor = texture(textureSampler, textureCoords);
	
	if(!passDitherTest(texColor.a * alpha)) discard;

	const vec3 pixelLight = max(light, texture(emissionTextureSampler, textureCoords).r*4);
	fragColor = texColor*vec4(pixelLight, 1);
}
