#version 330 

layout (location=0) out vec4 frag_color;

flat in vec4 color;
in vec2 unitPosition;

// Like smooth step, but with linear interpolation instead of s-curve.
float linearstep(float edge0, float edge1, float x) {
    return clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
}

void main(){
	float distSqr = sqrt(dot(unitPosition, unitPosition));
	float delta = fwidth(distSqr)/2;
	float alpha = linearstep(1+delta, 1-delta, distSqr);
	frag_color = color;
	frag_color.a *= alpha;
}