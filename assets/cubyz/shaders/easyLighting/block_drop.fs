#version 430

in vec3 outTexCoord;
in vec3 mvVertexPos;
in vec3 outLight;

out vec4 fragColor;

struct Fog {
	bool activ;
	vec3 color;
	float density;
};

uniform sampler2DArray texture_sampler;
uniform Fog fog;

vec4 ambientC;

void setupColors(vec3 textCoord) {
	ambientC = texture(texture_sampler, textCoord);
}

vec4 calcFog(vec3 pos, vec4 color, Fog fog) {
	float distance = length(pos);
	float fogFactor = 1.0/exp((distance*fog.density)*(distance*fog.density));
	fogFactor = clamp(fogFactor, 0.0, 1.0);
	vec3 resultColor = mix(fog.color, color.xyz, fogFactor);
	return vec4(resultColor.xyz, color.w);
}

void main() {
	setupColors(outTexCoord);
	
	fragColor = ambientC*vec4(outLight, 1);
	
	if (fog.activ) {
		fragColor = calcFog(mvVertexPos, fragColor, fog);
	}
}
