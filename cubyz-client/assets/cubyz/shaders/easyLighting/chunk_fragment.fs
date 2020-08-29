#version 330

in vec3 mvVertexPos;
flat in vec3 outColor;

out vec4 fragColor;

struct Fog {
	bool activ;
	vec3 color;
	float density;
};

uniform Fog fog;

vec4 calcFog(vec3 pos, vec4 color, Fog fog) {
	float distance = length(pos);
	float fogFactor = 1.0/exp((distance*fog.density)*(distance*fog.density));
	fogFactor = clamp(fogFactor, 0.0, 1.0);
	vec3 resultColor = mix(fog.color, color.xyz, fogFactor);
	return vec4(resultColor.xyz, color.w);
}

void main()
{
    fragColor = vec4(outColor, 1);
    
    if(fog.activ) {
        fragColor = calcFog(mvVertexPos, fragColor, fog);
    }
}
