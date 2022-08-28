#version 330 

layout (location=0) out vec4 frag_color;
uniform sampler2D image;

flat in vec4 fColor;
in vec2 uv;

void main() {
	frag_color = texture(image, uv) * fColor;
}