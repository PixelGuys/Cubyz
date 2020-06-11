#version 330

in vec2 outTexCoord;
in vec3 outColor;
in vec3 mvVertexPos;
in float outSelected;

out vec4 fragColor;

struct Fog {
	int activ;
	vec3 colour;
	float density;
};

uniform sampler2D texture_sampler;
uniform sampler2D break_sampler;
uniform bool materialHasTexture;
uniform Fog fog;

vec4 ambientC;

void setupColours( bool materialHasTexture, vec2 textCoord)
{
    if (materialHasTexture)
    {
        ambientC = texture(texture_sampler, textCoord);
        vec4 data = texture(break_sampler, textCoord);
        if (outSelected > 0 && outSelected < 1) { // selected value (being a float) is re-used for breaking animation
        	ambientC += data;
        }
    }
    else
    {
        ambientC = vec4(1, 1, 1, 1);
    }
}

vec4 calcFog(vec3 pos, vec4 colour, Fog fog) {
	float distance = length(pos);
	float fogFactor = 1.0 / exp((distance * fog.density) * (distance * fog.density));
	fogFactor = clamp(fogFactor, 0.0, 1.0);
	vec3 resultColour = mix(fog.colour, colour.xyz, fogFactor);
	return vec4(resultColour.xyz, colour.w);
}

void main()
{
    setupColours(materialHasTexture, outTexCoord);
    
    fragColor = ambientC * vec4(outColor, 1);
    
    if (fog.activ == 1) {
        fragColor = calcFog(mvVertexPos, fragColor, fog);
    }
    
    if (outSelected > 0) {
    	fragColor.z += 0.4;
    }
}
