#version 330

in vec2 outTexCoord;
in vec3 outColor;
in vec3 mvVertexPos;
in float outSelected;
flat in int selectionData;

out vec4 fragColor;

struct Fog {
	bool activ;
	vec3 color;
	float density;
};

uniform sampler2D texture_sampler;
uniform sampler2D break_sampler;
uniform bool materialHasTexture;
uniform Fog fog;
uniform bool hasAtlas;
uniform int atlasSize;

vec4 ambientC;

void setupColors(bool materialHasTexture, vec2 textCoord)
{
	if(hasAtlas) {
        ambientC = texture(texture_sampler, (textCoord + vec2((selectionData >> 8) & 255, (selectionData >> 0) & 255))/atlasSize); // selectionData is also being used for the texture atlas position, to reduce data transfer.
        vec4 data = texture(break_sampler, textCoord);
        if (((selectionData >> 24) & 255) != 0 && ((selectionData >> 24) & 255) != 255) { // selected value is re-used for breaking animation
        	ambientC += data;
        }
	} else if(materialHasTexture) {
        ambientC = texture(texture_sampler, textCoord);
        vec4 data = texture(break_sampler, textCoord);
        if (((selectionData >> 24) & 255) != 0 && ((selectionData >> 24) & 255) != 255) { // selected value is re-used for breaking animation
        	ambientC += data;
        }
    }
    else {
        ambientC = vec4(1, 1, 1, 1);
    }
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
    setupColors(materialHasTexture, outTexCoord);
    
    fragColor = ambientC*vec4(outColor, 1);
    
    if(fog.activ) {
        fragColor = calcFog(mvVertexPos, fragColor, fog);
    }
    
    if(((selectionData >> 24) & 255) != 0) {
    	fragColor.z += 0.4;
    }
}
