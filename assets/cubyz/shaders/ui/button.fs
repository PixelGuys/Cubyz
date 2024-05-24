#version 330 

layout (location=0) out vec4 frag_color;
uniform sampler2D image;

flat in vec4 fColor;
in vec2 startCoord;

uniform float scale;

void main() {
	frag_color = texture(image, (gl_FragCoord.xy - startCoord)/(2*scale)/textureSize(image, 0));
	frag_color.a *= fColor.a;
	frag_color.rgb += fColor.rgb;
}