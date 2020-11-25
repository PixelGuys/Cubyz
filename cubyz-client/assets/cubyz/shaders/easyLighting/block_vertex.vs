#version 330

layout (location=0)  in vec3 position;
layout (location=1)  in vec2 texCoord;
layout (location=2)  in vec3 vertexNormal;
layout (location=3)  in mat3x4 modelViewMatrix;
layout (location=6)  in int easyLight[8];
layout (location=14) in int selected;

out vec2 outTexCoord;
out vec3 mvVertexPos;
out vec3 outColor;
flat out int selectionData;

uniform mat4 projectionMatrix;
uniform vec3 ambientLight;
uniform vec3 directionalLight;
uniform mat4 viewMatrix;

vec3 calcLight(int srgb)
{
    float s = (srgb >> 24) & 255;
    float r = (srgb >> 16) & 255;
    float g = (srgb >> 8) & 255;
    float b = (srgb >> 0) & 255;
    s = s*(1 - dot(directionalLight, vertexNormal));
    r = max(s*ambientLight.x, r);
    g = max(s*ambientLight.y, g);
    b = max(s*ambientLight.z, b);
    return vec3(r, g, b);
}

void main()
{
	selectionData = selected;
	outColor = 0.003890625*(
						(1 - position.x)*(
							(1 - position.y)*(
								  (1 - position.z)*calcLight(easyLight[0])
								+ (position.z)*calcLight(easyLight[1])
							) + (position.y)*(
								  (1 - position.z)*calcLight(easyLight[2])
								+ (position.z)*calcLight(easyLight[3])
							)
						) + (position.x)*(
							(1 - position.y)*(
								(1 - position.z)*calcLight(easyLight[4])
								+(position.z)*calcLight(easyLight[5])
							) + (position.y)*(
								  (1 - position.z)*calcLight(easyLight[6])
								+ (position.z)*calcLight(easyLight[7])
							)
						));
	vec4 mvPos = viewMatrix*vec4(vec4(position, 1)*modelViewMatrix, 1);
	gl_Position = projectionMatrix*mvPos;
    outTexCoord = texCoord;
    mvVertexPos = mvPos.xyz;
}
