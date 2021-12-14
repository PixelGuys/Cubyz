#version 330

layout (location=0)  in vec3 position;
layout (location=1)  in vec2 texCoord;
layout (location=2)  in vec3 vertexNormal;

out vec3 outTexCoord;
out vec3 mvVertexNormal;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;

uniform int texPosX;
uniform int texNegX;
uniform int texPosY;
uniform int texNegY;
uniform int texPosZ;
uniform int texNegZ;

void main()
{
	vec4 mvPos = viewMatrix*vec4(position, 1);
	gl_Position = projectionMatrix*mvPos;
   	mvVertexNormal = normalize(viewMatrix*vec4(vertexNormal, 0.0)).xyz;
	int texture = 0;
	if (vertexNormal == vec3(1, 0, 0)) {
		texture = texPosX;
	} else if (vertexNormal == vec3(-1, 0, 0)) {
		texture = texNegX;
	} else if (vertexNormal == vec3(0, 1, 0)) {
		texture = texPosY;
	} else if (vertexNormal == vec3(0, -1, 0)) {
		texture = texNegY;
	} else if (vertexNormal == vec3(0, 0, 1)) {
		texture = texPosZ;
	} else if (vertexNormal == vec3(0, 0, -1)) {
		texture = texNegZ;
	} else {
		texture = texNegX;
	}
    outTexCoord = vec3(texCoord, float(texture));
}