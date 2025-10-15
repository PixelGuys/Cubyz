#version 460

layout (location = 0) in vec3 position;
layout (location = 1) in vec2 uv;

layout (location = 0) uniform mat4 mvp;

layout (location = 0) out vec2 texCoord;
layout (location = 1) out float fragDistance;

void main() {
	gl_Position = mvp * vec4(position, 1.0);
	texCoord = uv;
	
	// Calculate distance from origin (billboard center) for fog
	// The celestial objects are at a fixed distance (celestialDistance)
	fragDistance = length(position);
}
