#version 460

layout(location = 0) out vec3 mvVertexPos;

layout(location = 0) uniform mat4 projectionMatrix;
layout(location = 1) uniform mat4 viewMatrix;
layout(location = 2) uniform vec3 modelPosition;
layout(location = 3) uniform vec3 lowerBounds;
layout(location = 4) uniform vec3 upperBounds;
layout(location = 5) uniform float lineSize;

vec3 offsetVertices[] = vec3[] (
	vec3(-1, -1, -1),
	vec3(-1, -1, 1),
	vec3(-1, 1, -1),
	vec3(-1, 1, 1),
	vec3(1, -1, -1),
	vec3(1, -1, 1),
	vec3(1, 1, -1),
	vec3(1, 1, 1),

	vec3(-1, -1, -1),
	vec3(-1, -1, 1),
	vec3(1, -1, -1),
	vec3(1, -1, 1),
	vec3(-1, 1, -1),
	vec3(-1, 1, 1),
	vec3(1, 1, -1),
	vec3(1, 1, 1),

	vec3(-1, -1, -1),
	vec3(-1, 1, -1),
	vec3(1, -1, -1),
	vec3(1, 1, -1),
	vec3(-1, -1, 1),
	vec3(-1, 1, 1),
	vec3(1, -1, 1),
	vec3(1, 1, 1)
);

vec3 lineVertices[] = vec3[] (
	vec3(0, 0, 0),
	vec3(0, 0, 1),
	vec3(0, 1, 0),
	vec3(0, 1, 1),
	vec3(1, 0, 0),
	vec3(1, 0, 1),
	vec3(1, 1, 0),
	vec3(1, 1, 1),

	vec3(0, 0, 0),
	vec3(0, 1, 0),
	vec3(0, 0, 1),
	vec3(0, 1, 1),
	vec3(1, 0, 0),
	vec3(1, 1, 0),
	vec3(1, 0, 1),
	vec3(1, 1, 1),

	vec3(0, 0, 0),
	vec3(1, 0, 0),
	vec3(0, 0, 1),
	vec3(1, 0, 1),
	vec3(0, 1, 0),
	vec3(1, 1, 0),
	vec3(0, 1, 1),
	vec3(1, 1, 1)
);

void main() {
	int vertexIndex = gl_VertexID%24;
	int lineIndex = gl_VertexID/24;
	vec3 lineStart = lineVertices[lineIndex*2];
	vec3 lineEnd = lineVertices[lineIndex*2 + 1];
	vec3 lineCenter = (lineStart + lineEnd)/2*(upperBounds - lowerBounds);

	vec3 offsetVector = vec3(lineSize);
	offsetVector += vec3(notEqual(lineStart, lineEnd))*(upperBounds - lowerBounds)/2;

	vec3 vertexPos = lineCenter + offsetVertices[vertexIndex]*offsetVector;
	vec4 mvPos = viewMatrix*vec4(lowerBounds + vertexPos + modelPosition, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
}
