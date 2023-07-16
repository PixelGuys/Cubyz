#version 430
out vec4 fragColor;
  
in vec2 texCoords;

uniform sampler2D color;

void main() {
	fragColor = texture(color, texCoords);
	float maxColor = max(0.25, max(fragColor.r, max(fragColor.g, fragColor.b)));
	fragColor.rgb = fragColor.rgb/maxColor;
}