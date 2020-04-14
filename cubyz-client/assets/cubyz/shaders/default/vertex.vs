#version 330

layout (location=0)  in vec3 position;
layout (location=1)  in vec2 texCoord;
layout (location=2)  in vec3 vertexNormal;
layout (location=3)  in mat4 modelViewInstancedMatrix;
layout (location=15)  in float selectedInstanced;
layout (location=7)  in int easyLight[8];
layout (location=10)  in mat4 modelLightViewMatrix;

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
uniform int cheapLighting;
uniform float selectedNonInstanced;
uniform mat4 modelViewNonInstancedMatrix;
uniform mat4 viewMatrixInstanced;
uniform mat4 lightViewMatrixInstanced;

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
	if (cheapLighting == 1) {
		outEasyLight = 0.003890625*(
							(0.5-position.x)*(
								(0.5-position.y)*(
									(0.5-position.z)*vec3((easyLight[0] >> 16) & 255, (easyLight[0] >> 8) & 255, (easyLight[0] >> 0) & 255)
									+(0.5+position.z)*vec3((easyLight[1] >> 16) & 255, (easyLight[1] >> 8) & 255, (easyLight[1] >> 0) & 255)
								) + (0.5+position.y)*(
									(0.5-position.z)*vec3((easyLight[2] >> 16) & 255, (easyLight[2] >> 8) & 255, (easyLight[2] >> 0) & 255)
									+(0.5+position.z)*vec3((easyLight[3] >> 16) & 255, (easyLight[3] >> 8) & 255, (easyLight[3] >> 0) & 255)
								)
							) + (0.5+position.x)*(
								(0.5-position.y)*(
									(0.5-position.z)*vec3((easyLight[4] >> 16) & 255, (easyLight[4] >> 8) & 255, (easyLight[4] >> 0) & 255)
									+(0.5+position.z)*vec3((easyLight[5] >> 16) & 255, (easyLight[5] >> 8) & 255, (easyLight[5] >> 0) & 255)
								) + (0.5+position.y)*(
									(0.5-position.z)*vec3((easyLight[6] >> 16) & 255, (easyLight[6] >> 8) & 255, (easyLight[6] >> 0) & 255)
									+(0.5+position.z)*vec3((easyLight[7] >> 16) & 255, (easyLight[7] >> 8) & 255, (easyLight[7] >> 0) & 255)
								)
							));
		easyLightEnabled = 1.0;
	}
	vec4 mvPos = modelViewMatrix * initPos;
	gl_Position = projectionMatrix * mvPos;
    outTexCoord = texCoord;
   	mvVertexNormal = normalize(modelViewMatrix * initNormal).xyz;
    mvVertexPos = mvPos.xyz;
    mlightviewVertexPos = orthoProjectionMatrix * lightViewMatrixInstanced * modelLightViewMatrix * initPos;
}
