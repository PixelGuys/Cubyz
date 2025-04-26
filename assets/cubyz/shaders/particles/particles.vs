#version 460

out vec3 light;

uniform vec3 ambientLight;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat4 billboardMatrix;
uniform ivec3 playerPositionInteger;
uniform vec3 playerPositionFraction;

struct ParticleData {
	vec3 pos;
	vec3 vel; // unused, but thats fine
	float lifeLeft;
	int typ;
    uint light;
    bool collides; // also unused
    uint uv;
};
layout(std430, binding = 12) buffer _particleData
{
	ParticleData particleData[];
};

const vec3 facePositions[4] = vec3[4]
(
    vec3(-0.5f, 0.5f, 0.0f),
	vec3(0.5f, -0.5f, 0.0f),
	vec3(0.5f, 0.5f, 0.0f),
	vec3(-0.5f, -0.5f, 0.0f)
);

int indices[6] = {0, 1, 2, 1, 0, 3};

void main() {
    int particleID = gl_VertexID / 6;
	int vertexID = gl_VertexID % 6;
    ParticleData particle = particleData[particleID];
	// vec3 sunLight = vec3(
	// 	fullLight >> 25 & 31u,
	// 	fullLight >> 20 & 31u,
	// 	fullLight >> 15 & 31u
	// );
	// vec3 blockLight = vec3(
	// 	fullLight >> 10 & 31u,
	// 	fullLight >> 5 & 31u,
	// 	fullLight >> 0 & 31u
	// );
	light = vec3(1.0, 1.0, 1.0); // max(sunLight*ambientLight, blockLight)/31;
	// isBackFace = encodedPositionAndLightIndex>>15 & 1;
	// ditherSeed = encodedPositionAndLightIndex & 15;

	// textureIndex = textureAndQuad & 65535;
	// int quadIndex = textureAndQuad >> 16;

	vec3 position = particle.pos;

	// normal = quads[quadIndex].normal;

	position += (billboardMatrix*vec4(facePositions[indices[vertexID]], 1.0)).xyz;
	position += vec3(particle.pos - playerPositionInteger);
	position -= playerPositionFraction;

	// direction = position;

	vec4 mvPos = viewMatrix*vec4(position, 1);
	gl_Position = projectionMatrix*mvPos;
	// mvVertexPos = mvPos.xyz;
	// distanceForLodCheck = length(mvPos.xyz) + voxelSize;
	// uv = quads[quadIndex].cornerUV[vertexID]*voxelSize;
	// opaqueInLod = quads[quadIndex].opaqueInLod;
}