#version 430

in vec3 light;
in float textureIndex;
in vec2 uv;

uniform sampler2DArray particleTextureSampler;
uniform sampler2DArray particleEmissionSampler;

layout(location = 0) out vec4 fragColor;

void main() {
    //fragColor =  //vec4(1.0, 1.0, 1.0, 1.0);

    vec3 textureCoords = vec3(uv, textureIndex);
    //texture(texture_sampler, outTexCoord)*vec4(outLight*lightVariation(normal), 1);
    // vec3 pixelLight = max(light, texture(particleEmissionSampler, textureCoords).r*4);
	fragColor = texture(particleTextureSampler, textureCoords)*vec4(light, 1);
    if(fragColor.a != 1) {
        discard;
    }
	// fragColor.rgb += pixelLight;

    //fragColor.a = 1;
}