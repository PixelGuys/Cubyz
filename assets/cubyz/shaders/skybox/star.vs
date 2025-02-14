#version 430

in vec3 pos;
in float vTemperature;
in float vMagnitude;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;

out float temperature;
out float magnitude;

void main() {
	gl_Position = projectionMatrix * viewMatrix * vec4(pos, 1);

	temperature = vTemperature;
	magnitude = vMagnitude;
}
