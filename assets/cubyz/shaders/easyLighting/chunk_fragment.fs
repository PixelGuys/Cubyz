#version 330

in vec3 mvVertexPos;
in vec3 outTexCoord;
in vec3 outNormal;

uniform vec3 directionalLight;
uniform vec3 ambientLight;
uniform sampler2DArray texture_sampler;

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
	return vec4(resultColor.xyz, color.w + 1 - fogFactor);
}

void main()
{
    fragColor = texture(texture_sampler, outTexCoord)*vec4((1 - dot(directionalLight, outNormal))*ambientLight, 1);
	if(fragColor.a <= 0.1f) discard;
	else fragColor.a = 1;
    
    if(fog.activ) {
        fragColor = calcFog(mvVertexPos, fragColor, fog);
    }
}
