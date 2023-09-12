#version 430

in vec2 outTexCoord;
in vec3 mvVertexPos;
in vec3 outLight;

out vec4 fragColor;

uniform sampler2D texture_sampler;
uniform bool materialHasTexture;
vec4 ambientC;

void setupColors(bool materialHasTexture, vec2 textCoord) {
	if (materialHasTexture)
	{
		ambientC = texture(texture_sampler, textCoord);
	}
	else
	{
		ambientC = vec4(1, 1, 1, 1);
	}
}

void main() {
	setupColors(materialHasTexture, outTexCoord);
	
	fragColor = ambientC*vec4(outLight, 1);
}
