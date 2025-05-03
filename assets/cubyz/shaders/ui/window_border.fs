#version 460

layout(location = 0) out vec4 frag_color;

layout(location = 0) flat in vec2 startCoord;
layout(location = 1) flat in vec2 endCoord;
layout(location = 2) flat in vec4 fColor;

layout(location = 0) uniform vec2 start;
layout(location = 1) uniform vec2 size;

layout(location = 4) uniform float scale;
layout(location = 5) uniform vec2 effectLength;

void main() {
	vec2 distanceToBorder = min(gl_FragCoord.xy - startCoord, endCoord - gl_FragCoord.xy)/effectLength/scale;
	float reducedDistance = distanceToBorder.x*distanceToBorder.y/(distanceToBorder.x + distanceToBorder.y); // Inspired by the reduced mass from physics, to give a sort of curvy look to the outline.
	float opacity = max(1 - reducedDistance, 0);
	frag_color = fColor*vec4(1, 1, 1, opacity);
}
