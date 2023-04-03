#version 330 

layout (location=0) out vec4 frag_color;

flat in vec4 fColor;
flat in vec2 startCoord;
flat in vec2 endCoord;

uniform vec2 start;
uniform vec2 size;
uniform float scale;
uniform vec2 effectLength;

void main() {
	vec2 distanceToBorder = min(gl_FragCoord.xy - startCoord, endCoord - gl_FragCoord.xy)/effectLength/scale;
	float reducedDistance = distanceToBorder.x*distanceToBorder.y/(distanceToBorder.x + distanceToBorder.y); // Inspired by the reduced mass from physics, to give a sort of curvy look to the outline.
	float opacity = max(1 - reducedDistance, 0);
	frag_color = fColor*vec4(1, 1, 1, opacity);
}