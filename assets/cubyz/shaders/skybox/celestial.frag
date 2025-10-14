#version 460

layout (location = 0) in vec2 texCoord;

layout (location = 1) uniform float celestialOpacity;
layout (location = 2) uniform vec3 celestialColor;

layout(location = 0, index = 0) out vec4 fragColor;

void main() {
    // Make a simple solid circle that's very visible
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(texCoord, center);
    
    if (dist < 0.5) {
        // Solid color inside the circle
        fragColor = vec4(celestialColor, celestialOpacity);
    } else {
        // Transparent outside
        discard;
    }
}