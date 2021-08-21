#version 330 

layout (location=0) out vec4 frag_color;
uniform sampler2D image;

in vec2 uv;

void main(){
	frag_color = texture(image, uv);
}