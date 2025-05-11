#version 460

layout(location = 0) in vec3 mvVertexPos;
layout(location = 1) in vec3 boxPos;
layout(location = 2) flat in vec3 boxSize;

layout(location = 0) out vec4 fragColor;

layout(location = 5) uniform float lineSize;

void main() {
	vec3 boxDistance = min(boxPos, boxSize - boxPos);
	bvec3 inRange = lessThan(boxDistance, vec3(lineSize));
	if(inRange.x && inRange.y || inRange.x && inRange.z || inRange.y && inRange.z) {
		fragColor = vec4(0, 0, 0, 1);
	} else {
		discard;
	}
}
