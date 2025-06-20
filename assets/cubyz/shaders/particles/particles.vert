#version 460

layout(location = 0) out vec3 textureCoords;
layout(location = 1) flat out vec3 light;

layout(location = 0) uniform vec3 ambientLight;
layout(location = 1) uniform mat4 projectionAndViewMatrix;
layout(location = 2) uniform mat4 billboardMatrix;

struct ParticleData {
	vec3 pos;
	float rotation;
	float lifeRatio;
	uint light;
	uint type;
};
layout(std430, binding = 13) restrict readonly buffer _particleData
{
	ParticleData particleData[];
};

struct ParticleTypeData {
	float animationFrames;
	float startFrame;
	float size;
};
layout(std430, binding = 14) restrict readonly buffer _particleTypeData
{
	ParticleTypeData particleTypeData[];
};

const vec2 uvPositions[4] = vec2[4]
(
	vec2(0.0f, 0.0f),
	vec2(1.0f, 0.0f),
	vec2(0.0f, 1.0f),
	vec2(1.0f, 1.0f)
);

const vec3 facePositions[4] = vec3[4]
(
	vec3(-0.5f, -0.5f, 0.0f),
	vec3(-0.5f, 0.5f, 0.0f),
	vec3(0.5f, -0.5f, 0.0f),
	vec3(0.5f, 0.5f, 0.0f)
);

void main() {
	int particleID = gl_VertexID >> 2;
	int vertexID = gl_VertexID & 3;
	ParticleData particle = particleData[particleID];
	ParticleTypeData particleType = particleTypeData[particle.type];

	uint fullLight = particle.light;
	vec3 sunLight = vec3(
		fullLight >> 25 & 31u,
		fullLight >> 20 & 31u,
		fullLight >> 15 & 31u
	);
	vec3 blockLight = vec3(
		fullLight >> 10 & 31u,
		fullLight >> 5 & 31u,
		fullLight >> 0 & 31u
	);
	light = max(sunLight*ambientLight, blockLight)/31;

	float rotation = particle.rotation;
	vec3 faceVertPos = facePositions[vertexID];
	float sn = sin(rotation);
	float cs = cos(rotation);
	const vec3 vertexRotationPos = vec3(
		faceVertPos.x*cs - faceVertPos.y*sn,
		faceVertPos.x*sn + faceVertPos.y*cs,
		0
	);

	const vec3 vertexPos = (billboardMatrix*vec4(particleType.size*vertexRotationPos, 1)).xyz + particle.pos;
	gl_Position = projectionAndViewMatrix*vec4(vertexPos, 1);

	float textureIndex = floor(particle.lifeRatio*particleType.animationFrames + particleType.startFrame);
	textureCoords = vec3(uvPositions[vertexID], textureIndex);
}
