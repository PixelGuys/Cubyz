#version 330

layout (location=0) in vec3 position;
layout (location=1) in vec2 texCoord;
layout (location=2) in vec3 vertexNormal;
layout (location=3) in mat4 modelLightViewInstancedMatrix;
layout (location=7) in float selectedInstanced;

uniform mat4 projectionMatrix;
uniform int isInstanced;
uniform mat4 modelLightViewNonInstancedMatrix;
uniform mat4 viewMatrixInstanced;

void main()
{
	mat4 modelViewMatrix;
	if (isInstanced == 1) {
		modelViewMatrix = viewMatrixInstanced * modelLightViewInstancedMatrix;
	} else {
		modelViewMatrix = modelLightViewNonInstancedMatrix;
	}
	gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
