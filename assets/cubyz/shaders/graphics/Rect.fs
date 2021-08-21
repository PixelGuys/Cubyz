#version 330 

layout (location=0) out vec4 frag_color;

flat in vec4 color;

void main(){
	frag_color = color;
}