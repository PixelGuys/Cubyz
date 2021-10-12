#version 330
out vec4 fragColor;
  
in vec2 texCoords;

uniform sampler2D color;
uniform sampler2D position;

void main() {
	fragColor = texture(color, texCoords);
}