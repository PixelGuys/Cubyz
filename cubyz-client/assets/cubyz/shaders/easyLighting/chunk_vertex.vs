#version 330

layout (location=0)  in int positionAndNormals;
layout (location=1)  in int color;

out vec3 mvVertexPos;
out vec3 outColor;
out vec3 outNormal;


uniform mat4 projectionMatrix;
uniform vec3 ambientLight;
uniform mat4 viewMatrix;
uniform vec3 modelPosition;

const vec3[6] normals = vec3[6](
	vec3(-1, 0, 0),
	vec3(1, 0, 0),
	vec3(0, 0, -1),
	vec3(0, 0, 1),
	vec3(0, -1, 0),
	vec3(0, 1, 0)
);

void main()
{
	int normal = positionAndNormals & 7;
	int x = (positionAndNormals >> 3) & 511;
	int y = (positionAndNormals >> 12) & 511;
	int z = (positionAndNormals >> 21) & 511;
	vec4 mvPos = viewMatrix*vec4(vec3(x, y, z) + modelPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	outColor = vec3(((color >> 8) & 15)/15.0, ((color >> 4) & 15)/15.0, ((color >> 0) & 15)/15.0)*ambientLight;
	outNormal = normals[normal];
    mvVertexPos = mvPos.xyz;
}