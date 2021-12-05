#version 430

layout(location = 0) out vec4 fragColor;

in vec2 texCoords;

struct Fog {
	bool activ;
	vec3 color;
	float density;
};

uniform Fog fog;

uniform sampler2D color;
uniform sampler2D position;

vec4 calcFog(vec3 pos, vec4 color, Fog fog) {
	float distance = length(pos);
	float fogFactor = 1.0/exp((distance*fog.density)*(distance*fog.density));
	fogFactor = clamp(fogFactor, 0.0, 1.0);
	vec3 resultColor = mix(fog.color, color.xyz, fogFactor);
	return vec4(resultColor.xyz, color.w + 1 - fogFactor);
}

void main() {
	fragColor = calcFog(texture(position, texCoords).xyz, texture(color, texCoords), fog);
}