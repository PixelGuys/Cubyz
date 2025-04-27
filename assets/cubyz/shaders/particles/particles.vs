#version 460

out vec3 light;
out float textureIndex;
out vec2 uv;

uniform vec3 ambientLight;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat4 billboardMatrix;
uniform ivec3 playerPositionInteger;
uniform vec3 playerPositionFraction;

struct ParticleData {
	vec3 pos;
	float align1; // DO NOT REMOVE THAT
	vec3 vel; // unused, but thats fine
	float align2;
	float lifeTime;
	float lifeLeft;
	uint typ;
    uint light;
    bool collides; // also unused
    // uint uv;
};
layout(std430, binding = 12) buffer _particleData
{
	ParticleData particleData[];
};
struct ParticleTypeData {
	uint texture;
	uint animationFrames;
	uint startFrame;
	bool isBlockTexture;
};
layout(std430, binding = 13) buffer _particleTypeData
{
	ParticleTypeData particleTypeData[];
};

const vec2 uvPositions[4] = vec2[4]
(
    vec2(0f, 1f),
	vec2(1f, 0f),
	vec2(1f, 1f),
	vec2(0f, 0f)
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
    int particleID = gl_VertexID / 6;
	int vertexID = gl_VertexID % 6;
    ParticleData particle = particleData[particleID];
	ParticleTypeData particleType = particleTypeData[particle.typ];
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
	

	textureIndex = floor(float(particleType.startFrame) + (particle.lifeLeft / particle.lifeTime) * float(particleType.animationFrames));

	vec3 position = particle.pos;

	position += (billboardMatrix*vec4(facePositions[indices[vertexID]], 1.0)).xyz;
	position += vec3(particle.pos - playerPositionInteger);
	position -= playerPositionFraction;

	vec4 mvPos = viewMatrix*vec4(position, 1);
	gl_Position = projectionMatrix*mvPos;

	uv = uvPositions[indices[vertexID]];

	// mvVertexPos = mvPos.xyz;
	// distanceForLodCheck = length(mvPos.xyz) + voxelSize;
	// uv = quads[quadIndex].cornerUV[vertexID]*voxelSize;
	// opaqueInLod = quads[quadIndex].opaqueInLod;
}