#version 430

layout(location=0) out vec4 fragColor;

in vec2 texCoords;

layout(binding = 3) uniform sampler2D color;

float weights[16] = float[] (0.14804608426116522, 0.14511457538105424, 0.13666376040001485, 0.12365848409943446, 0.10750352152877563, 0.08979448915479665, 0.07206176550016223, 0.055563338564704794, 0.041162333610640485, 0.029298127479707798, 0.02003585874555622, 0.01316449727103141, 0.008310531828522687, 0.005040592352516703, 0.002937396384358805, 0.001644643437557613);

void main() {
	vec2 tex_offset = 1.0/textureSize(color, 0);
	vec3 result = texture(color, texCoords).rgb * weights[0];
	for(int i = 1; i < 16; i++) {
		result += texture(color, texCoords + vec2(tex_offset.x * i, 0.0)).rgb * weights[i];
		result += texture(color, texCoords - vec2(tex_offset.x * i, 0.0)).rgb * weights[i];
	}
	fragColor = vec4(result, 1);
}