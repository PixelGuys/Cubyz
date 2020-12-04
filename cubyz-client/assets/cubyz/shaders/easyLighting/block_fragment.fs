#version 330

in vec2 outTexCoord;
in vec3 outColor;
in vec3 mvVertexPos;
flat in int selectionIndex;

out vec4 fragColor;

struct Fog {
	bool activ;
	vec3 color;
	float density;
};

uniform sampler2D texture_sampler;
uniform sampler2D break_sampler;
uniform Fog fog;
uniform int selectedIndex;
uniform int atlasSize;

vec4 ambientC;

void setupColors(vec2 textCoord)
{
	vec4 bg = texture(texture_sampler, textCoord);
	ambientC = texture(break_sampler, fract(textCoord*atlasSize))*float(selectedIndex == selectionIndex);
	ambientC = vec4(mix(vec4(bg), vec4(ambientC), ambientC.a));
}

vec4 calcFog(vec3 pos, vec4 color, Fog fog) {
	float distance = length(pos);
	float fogFactor = 1.0/exp((distance*fog.density)*(distance*fog.density));
	fogFactor = clamp(fogFactor, 0.0, 1.0);
	vec3 resultColor = mix(fog.color, color.xyz, fogFactor);
	return vec4(resultColor.xyz, color.w);
}

void main()
{
	setupColors(outTexCoord);
	
	fragColor = ambientC*vec4(outColor, 1);
	
	if(fog.activ) {
		fragColor = calcFog(mvVertexPos, fragColor, fog);
	}
}
