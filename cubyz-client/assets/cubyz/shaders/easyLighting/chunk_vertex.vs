#version 330

layout (location=0)  in vec3 position;
layout (location=1)  in int color;

out vec3 mvVertexPos;
out vec3 outColor;


uniform mat4 projectionMatrix;
uniform vec3 ambientLight;
uniform mat4 viewMatrix;

void main()
{
	vec4 mvPos = viewMatrix*vec4(position, 1);
	gl_Position = projectionMatrix*mvPos;
	outColor = vec3(((color >> 8) & 15)/15.0, ((color >> 4) & 15)/15.0, ((color >> 0) & 15)/15.0);
	if(ambientLight.x == 0.646893)
	outColor += vec3(01, 0, 0);
    mvVertexPos = mvPos.xyz;
}