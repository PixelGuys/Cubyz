#version 330

layout (location=0)  in vec3 position;
layout (location=1)  in vec2 texCoord;
layout (location=2)  in vec3 vertexNormal;
layout (location=3)  in mat4 modelViewInstancedMatrix;
layout (location=7)  in float selectedInstanced;
layout (location=8)  in mat4 modelLightViewMatrix;
layout (location=12) in vec3 easyLight;

out vec2 outTexCoord;
out vec3 mvVertexNormal;
out vec3 mvVertexPos;
out float outSelected;
out float easyLightEnabled;
out vec4 mlightviewVertexPos;
out vec3 outEasyLight;

uniform mat4 projectionMatrix;
uniform mat4 orthoProjectionMatrix;
uniform int isInstanced;
uniform int cheapLightning;
uniform float selectedNonInstanced;
uniform mat4 modelViewNonInstancedMatrix;
uniform mat4 viewMatrixInstanced;

void main()
{
	vec4 initPos = vec4(position, 1);
	vec4 initNormal = vec4(vertexNormal, 0.0);
	mat4 modelViewMatrix;
	if (isInstanced == 1) {
		modelViewMatrix = viewMatrixInstanced * modelViewInstancedMatrix;
		outSelected = selectedInstanced;
	} else {
		outSelected = selectedNonInstanced;
		modelViewMatrix = modelViewNonInstancedMatrix;
	}
	if (cheapLightning == 1) {
		outEasyLight = easyLight;
		easyLightEnabled = 1.0;
	}
	vec4 mvPos = modelViewMatrix * initPos;
	gl_Position = projectionMatrix * mvPos;
    outTexCoord = texCoord;
   	mvVertexNormal = normalize(modelViewMatrix * initNormal).xyz;
    mvVertexPos = mvPos.xyz;
    mlightviewVertexPos = orthoProjectionMatrix * modelLightViewMatrix * vec4(position, 1.0);
}
