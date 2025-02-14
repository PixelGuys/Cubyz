#version 430

in vec3 vPos;
in float vTemperature;
in float vMagnitude;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;

out vec3 mvVertexPos;
out float temperature;
out float magnitude;
out vec3 direction;

void main() {
	vec4 mvPos = viewMatrix*vec4(vPos, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;

	temperature = vTemperature;
	magnitude = vMagnitude;
	direction = vPos;
}
