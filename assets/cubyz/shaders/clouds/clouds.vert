#version 460

#include "frame_uniforms.glsl"

#ifdef OPEN_GL
#define gl_InstanceIndex gl_InstanceID
#endif

layout(location = 0) out vec3 worldPos;
layout(location = 1) flat out vec3 cloudMin;
layout(location = 2) flat out vec3 cloudSize;
layout(location = 3) flat out vec3 faceNormal;

struct CloudData {
	vec4 min;
	vec4 size;
};

layout(std430, binding = 16) readonly buffer _clouds
{
	CloudData clouds[];
};

const vec3 positions[36] = vec3[36](
	vec3(0, 0, 1), vec3(1, 0, 1), vec3(1, 1, 1),
	vec3(0, 0, 1), vec3(1, 1, 1), vec3(0, 1, 1),

	vec3(0, 0, 0), vec3(1, 1, 0), vec3(1, 0, 0),
	vec3(0, 0, 0), vec3(0, 1, 0), vec3(1, 1, 0),

	vec3(1, 0, 0), vec3(1, 1, 0), vec3(1, 1, 1),
	vec3(1, 0, 0), vec3(1, 1, 1), vec3(1, 0, 1),

	vec3(0, 0, 0), vec3(0, 1, 1), vec3(0, 1, 0),
	vec3(0, 0, 0), vec3(0, 0, 1), vec3(0, 1, 1),

	vec3(0, 1, 0), vec3(0, 1, 1), vec3(1, 1, 1),
	vec3(0, 1, 0), vec3(1, 1, 1), vec3(1, 1, 0),

	vec3(0, 0, 0), vec3(1, 0, 0), vec3(1, 0, 1),
	vec3(0, 0, 0), vec3(1, 0, 1), vec3(0, 0, 1)
);

const vec3 normals[6] = vec3[6](
	vec3(0, 0, 1),
	vec3(0, 0, -1),
	vec3(1, 0, 0),
	vec3(-1, 0, 0),
	vec3(0, 1, 0),
	vec3(0, -1, 0)
);

void main() {
	CloudData cloud = clouds[gl_InstanceIndex];
	vec3 localPos = positions[gl_VertexIndex];
	worldPos = cloud.min.xyz + localPos*cloud.size.xyz;
	cloudMin = cloud.min.xyz;
	cloudSize = cloud.size.xyz;
	vec4 cameraSpace = viewMatrix*vec4(worldPos, 1);
	gl_Position = projectionMatrix*cameraSpace;
	faceNormal = normals[gl_VertexIndex/6];
}
