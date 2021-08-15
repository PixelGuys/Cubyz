#version 330

in vec2 outTexCoord;
in vec3 mvVertexPos;
in vec3 mvVertexNormal;

out vec4 fragColor;

uniform sampler2D texture_sampler;
uniform vec3 light;
uniform vec3 dirLight;

void main()
{
    fragColor = texture(texture_sampler, outTexCoord)*vec4(light*(dot(dirLight, mvVertexNormal)*0.5 + 0.5), 1);
}
