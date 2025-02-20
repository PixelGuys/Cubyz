#version 430

layout(location=0) out vec4 fragColor;

in vec2 texCoords;

layout(binding = 3) uniform sampler2D color;

float weights[8] = float[] (2.275305315223722e-01, 2.164337365563677e-01, 1.862862434215453e-01, 1.450798722521298e-01, 1.0223605803398833e-01, 6.518858871330833e-02, 3.7610543897114775e-02, 1.963442560317357e-02);

void main() {
	vec2 tex_offset = 1.0/textureSize(color, 0);
	vec3 result = texture(color, texCoords).rgb * weights[0];
	for(int i = 1; i < 8; i++) {
		result += texture(color, texCoords + vec2(0, tex_offset.y * i)).rgb * weights[i];
		result += texture(color, texCoords - vec2(0, tex_offset.y * i)).rgb * weights[i];
	}
	fragColor = vec4(result, 1);
}
