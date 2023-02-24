#version 330 

layout (location=0) out vec4 frag_color;
uniform sampler2D image;

flat in vec4 fColor;
in vec2 startCoord;

uniform bool pressed;
uniform float scale;
uniform vec2 randomOffset;

void main() {
	frag_color = texture(image, (gl_FragCoord.xy - startCoord)/(2*scale)/textureSize(image, 0) + randomOffset);
	frag_color.a *= fColor.a;
	frag_color.rgb += fColor.rgb;
	if(pressed) {
		frag_color.rgb *= 0.8;
	}
}