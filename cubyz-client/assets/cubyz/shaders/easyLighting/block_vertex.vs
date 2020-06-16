#version 330

layout (location=0)  in vec3 position;
layout (location=1)  in vec2 texCoord;
layout (location=2)  in vec3 vertexNormal;
layout (location=3)  in mat4 modelViewMatrix;
layout (location=7)  in int easyLight[8];
layout (location=15) in float selected;

out vec2 outTexCoord;
out vec3 mvVertexPos;
out float outSelected;
out vec3 outColor;

uniform mat4 projectionMatrix;
uniform vec3 ambientLight;
uniform mat4 viewMatrix;

vec3 calcLight(int srgb)
{
    float s = (srgb >> 24) & 255;
    float r = (srgb >> 16) & 255;
    float g = (srgb >> 8) & 255;
    float b = (srgb >> 0) & 255;
    r = max(s*ambientLight.x, r);
    g = max(s*ambientLight.y, g);
    b = max(s*ambientLight.z, b);
    return vec3(r, g, b);
}

void main()
{
	outSelected = selected;
	outColor = 0.003890625*(
						(0.5-position.x)*(
							(0.5-position.y)*(
								(0.5-position.z)*calcLight(easyLight[0])
								+(0.5+position.z)*calcLight(easyLight[1])
							) + (0.5+position.y)*(
								(0.5-position.z)*calcLight(easyLight[2])
								+(0.5+position.z)*calcLight(easyLight[3])
							)
						) + (0.5+position.x)*(
							(0.5-position.y)*(
								(0.5-position.z)*calcLight(easyLight[4])
								+(0.5+position.z)*calcLight(easyLight[5])
							) + (0.5+position.y)*(
								(0.5-position.z)*calcLight(easyLight[6])
								+(0.5+position.z)*calcLight(easyLight[7])
							)
						));
	vec4 mvPos = viewMatrix * modelViewMatrix * vec4(position, 1);
	gl_Position = projectionMatrix * mvPos;
    outTexCoord = texCoord;
    mvVertexPos = mvPos.xyz;
}
