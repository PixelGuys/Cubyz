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
out vec4 mlightviewVertexPos;
out vec3 outColor;

uniform mat4 projectionMatrix;
uniform mat4 orthoProjectionMatrix;
uniform int isInstanced;
uniform int cheapLighting;
uniform float selectedNonInstanced;
uniform vec3 ambientLight;
uniform mat4 modelViewNonInstancedMatrix;
uniform mat4 viewMatrixInstanced;
uniform mat4 lightViewMatrixInstanced;

vec3 calcLight(int srgb)
{
    float s = (srgb >> 24) & 255;
    float r = (srgb >> 16) & 255;
    float g = (srgb >> 8) & 255;
    float b = (srgb >> 0) & 255;
    r = max(s*ambientLight.x, r);
    g = max(s*ambientLight.y, g);
    b = max(s*ambientLight.z, b);
    return vec3(r, g, b);
}

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
		outColor = 0.003890625*(
							(0.5-position.x)*(
								(0.5-position.y)*(
									(0.5-position.z)*calcLight(easyLight[0])
									+(0.5+position.z)*calcLight(easyLight[1])
								) + (0.5+position.y)*(
									(0.5-position.z)*calcLight(easyLight[2])
									+(0.5+position.z)*calcLight(easyLight[3])
								)
							) + (0.5+position.x)*(
								(0.5-position.y)*(
									(0.5-position.z)*calcLight(easyLight[4])
									+(0.5+position.z)*calcLight(easyLight[5])
								) + (0.5+position.y)*(
									(0.5-position.z)*calcLight(easyLight[6])
									+(0.5+position.z)*calcLight(easyLight[7])
								)
							));
	} else {
		outColor = ambientLight;
	}
	vec4 mvPos = modelViewMatrix * initPos;
	gl_Position = projectionMatrix * mvPos;
    outTexCoord = texCoord;
   	mvVertexNormal = normalize(modelViewMatrix * initNormal).xyz;
    mvVertexPos = mvPos.xyz;
    mlightviewVertexPos = orthoProjectionMatrix * lightViewMatrixInstanced * modelLightViewMatrix * initPos;
}
