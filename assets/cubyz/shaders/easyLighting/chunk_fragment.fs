#version 330

in vec3 mvVertexPos;
in vec2 outTexCoord;
flat in float textureIndex;
in vec3 outNormal;

uniform vec3 directionalLight;
uniform vec3 ambientLight;
uniform sampler2DArray texture_sampler;

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 position;

struct Fog {
	bool activ;
	vec3 color;
	float density;
};

uniform Fog fog;
uniform Fog waterFog; // TODO: Select fog from texture

vec4 calcFog(vec3 pos, vec4 color, Fog fog) {
	float distance = length(pos);
	float fogFactor = 1.0/exp((distance*fog.density)*(distance*fog.density));
	fogFactor = clamp(fogFactor, 0.0, 1.0);
	vec3 resultColor = mix(fog.color, color.xyz, fogFactor);
	return vec4(resultColor.xyz, color.w + 1 - fogFactor);
}

void main()
{
	fragColor = texture(texture_sampler, vec3(outTexCoord, textureIndex))*vec4((1 - dot(directionalLight, outNormal))*ambientLight, 1);
	if (fragColor.a <= 0.1f) discard;
	if (fog.activ) {

		// Underwater fog in lod(assumes that the fog is maximal):
		fragColor = vec4((1 - fragColor.a) * waterFog.color.xyz + fragColor.a * fragColor.xyz, 1);
	}
	
	if (fog.activ) {
		fragColor = calcFog(mvVertexPos, fragColor, fog);
	}
	position = vec4(mvVertexPos, 1);
}
