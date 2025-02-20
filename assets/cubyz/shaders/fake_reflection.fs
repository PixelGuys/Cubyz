#version 430

in vec3 coords;

out vec4 fragColor;

uniform vec3 normalVector;
uniform vec3 upVector;
uniform vec3 rightVector;
uniform float frequency;

ivec3 random3to3(ivec3 v) {
	v &= 15;
	ivec3 fac = ivec3(11248723, 105436839, 45399083);
	int seed = v.x*fac.x ^ v.y*fac.y ^ v.z*fac.z;
	v = seed*fac;
	return v;
}

float snoise(vec3 v) {
	const vec2 C = vec2(1.0/6.0, 1.0/3.0);

	// First corner
	vec3 i = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);

	// Other corners
	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);

	// x0 = x0 - 0. + 0.0 * C
	vec3 x1 = x0 - i1 + 1.0*C.xxx;
	vec3 x2 = x0 - i2 + 2.0*C.xxx;
	vec3 x3 = x0 - 1. + 3.0*C.xxx;

	// Get gradients:
	ivec3 rand = random3to3(ivec3(i));
	vec3 p0 = vec3(rand);

	rand = random3to3((ivec3(i + i1)));
	vec3 p1 = vec3(rand);

	rand = random3to3((ivec3(i + i2)));
	vec3 p2 = vec3(rand);

	rand = random3to3((ivec3(i + 1)));
	vec3 p3 = vec3(rand);

	// Mix final noise value
	vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
	m = m*m;
	return 42.0*dot(m*m, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)))/(1 << 31);
}

void main() {
	vec3 position = normalize(coords);
	position = position.x*rightVector + position.y*upVector + position.z*normalVector;
	position *= frequency;
	fragColor = vec4(vec3(snoise(position)*0.5 + 0.5), 1);
}
