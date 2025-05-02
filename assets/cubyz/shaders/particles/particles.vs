#version 460

out vec3 light;
out vec2 uv;
out float textureIndex;

uniform vec3 ambientLight;
uniform mat4 projectionAndViewMatrix;
uniform mat4 billboardMatrix;
uniform ivec3 playerPositionInteger;
uniform vec3 playerPositionFraction;

struct ParticleData {
	vec3 pos;
	float rot;
	float lifeTime;
	float lifeLeft;
	uint light;
	uint typ;
};
layout(std430, binding = 13) restrict readonly buffer _particleData
{
	ParticleData particleData[];
};

struct ParticleTypeData {
	uint texture;
	uint animationFrames;
	uint startFrame;
	float size;
	bool isBlockTexture;
};
layout(std430, binding = 14) restrict readonly buffer _particleTypeData
{
	ParticleTypeData particleTypeData[];
};

const vec2 uvPositions[4] = vec2[4]
(
	vec2(0.0f, 0.0f),
	vec2(1.0f, 1.0f),
	vec2(0.0f, 1.0f),
	vec2(1.0f, 0.0f)
);

const vec3 facePositions[4] = vec3[4]
(
	vec3(-0.5f, 0.5f, 0.0f),
	vec3(0.5f, -0.5f, 0.0f),
	vec3(0.5f, 0.5f, 0.0f),
	vec3(-0.5f, -0.5f, 0.0f)
);

const int indices[6] = int[6](0, 1, 2, 1, 0, 3);

void main() {
	int particleID = gl_VertexID/6;
	int vertexID = gl_VertexID%6;
	ParticleData particle = particleData[particleID];
	ParticleTypeData particleType = particleTypeData[particle.typ];

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
	light = max(sunLight*ambientLight, blockLight)*0.032258064516129; // 1/31 im not sure if we keep this

	textureIndex = floor(float(particleType.startFrame) + (particle.lifeLeft/particle.lifeTime)*float(particleType.animationFrames));

	float rot = particle.rot;
	vec3 pos = facePositions[indices[vertexID]];
	float sn = sin(rot);
	float cs = cos(rot);
	vec3 position = vec3(0);
	position.x = pos.x*cs - pos.y*sn;
	position.y = pos.x*sn + pos.y*cs;

	position = (billboardMatrix*vec4(particleType.size*position, 1)).xyz;
	position += vec3(particle.pos - playerPositionInteger);
	position -= playerPositionFraction;

	gl_Position = projectionAndViewMatrix*vec4(position, 1);

	uv = uvPositions[indices[vertexID]];
}
