#version 330

void main() {
	gl_FragDepth = gl_FragCoord.z;
}
