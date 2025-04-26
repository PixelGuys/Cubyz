#version 460

in vec3 light;

layout(location = 0) out vec4 fragColor;

void main() {
    fragColor = vec4(1.0, 1.0, 1.0, 1.0);
}