#version 430

in vec2 outTexCoord;
flat in float textureIndex;
in vec3 outColor;
in vec3 mvVertexPos;

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 position;

struct Fog {
	bool activ;
	vec3 color;
	float density;
};

uniform sampler2DArray texture_sampler;
uniform Fog fog;
uniform int selectedIndex;

vec4 ambientC;

void setupColors(vec3 textCoord) {
	ambientC = texture(texture_sampler, textCoord);
}

vec4 calcFog(vec3 pos, vec4 color, Fog fog) {
	float distance = length(pos);
	float fogFactor = 1.0/exp((distance*fog.density)*(distance*fog.density));
	fogFactor = clamp(fogFactor, 0.0, 1.0);
	vec3 resultColor = mix(fog.color, color.xyz, fogFactor);
	return vec4(resultColor.xyz, color.w + 1 - fogFactor);
}

void main() {
	setupColors(vec3(outTexCoord, textureIndex));
	if (ambientC.a != 1) discard;

	fragColor = ambientC*vec4(outColor, 1);

	if (fog.activ) {
		fragColor = calcFog(mvVertexPos, fragColor, fog);
	}
	position = vec4(mvVertexPos, 1);
}
