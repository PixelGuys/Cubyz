#version 330

layout (location=0) in vec3 position;
layout (location=1) in vec2 texCoord;
layout (location=2) in vec3 vertexNormal;
//layout (location=5) in mat4 modelViewInstancedMatrix;
//layout (location=9) in mat4 modelLightViewInstancedMatrix;

out vec2 outTexCoord;
out vec3 mvVertexNormal;
out vec3 mvVertexPos;
out float outSelected;

uniform mat4 projectionMatrix;
uniform int isInstanced;
uniform float selectedInstanced;
uniform float selectedNonInstanced;
uniform mat4 modelViewNonInstancedMatrix;

void main()
{
	vec4 initPos = vec4(position, 1);
	vec4 initNormal = vec4(vertexNormal, 0.0);
	mat4 modelViewMatrix;
	//mat4 lightViewMatrix;
	if (false) {
		//modelViewMatrix = modelViewInstancedMatrix;
		//lightViewMatrix = modelLightViewInstancedMatrix;
		//outSelected = selectedInstanced;
	} else {
		outSelected = selectedNonInstanced;
		modelViewMatrix = modelViewNonInstancedMatrix;
	}
	vec4 mvPos = modelViewMatrix * initPos;
	gl_Position = projectionMatrix * mvPos;
    outTexCoord = texCoord;
   	mvVertexNormal = normalize(modelViewMatrix * initNormal).xyz;
    mvVertexPos = mvPos.xyz;
}
