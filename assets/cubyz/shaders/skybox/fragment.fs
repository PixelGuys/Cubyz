#version 330 

layout (location=0) out vec4 fragColor;

in vec3 pos;

#define PI 3.141592
#define iSteps 16
#define jSteps 8
#define ATMOS_SIZE 6371e3

uniform mat4 lightDir;
uniform mat4 invLightDir;
uniform float altitude;

vec2 rsi(vec3 r0, vec3 rd, float sr) {
    float a = dot(rd, rd);
    float b = 2.0 * dot(rd, r0);
    float c = dot(r0, r0) - (sr * sr);
    float d = (b*b) - 4.0*a*c;
    if (d < 0.0) return vec2(1e5,-1e5);
    return vec2(
        (-b - sqrt(d))/(2.0*a),
        (-b + sqrt(d))/(2.0*a)
    );
}

vec3 atmosphere(vec3 r, vec3 r0, vec3 pSun, float iSun, float rPlanet, float rAtmos, vec3 kRlh, float kMie, float shRlh, float shMie, float g) {
    pSun = normalize(pSun);
    r = normalize(r);

    vec2 p = rsi(r0, r, rAtmos);
    if (p.x > p.y) return vec3(0,0,0);
    p.y = min(p.y, rsi(r0, r, rPlanet).x);
    float iStepSize = (p.y - p.x) / float(iSteps);

    float iTime = 0.0;

    vec3 totalRlh = vec3(0,0,0);
    vec3 totalMie = vec3(0,0,0);

    float iOdRlh = 0.0;
    float iOdMie = 0.0;

    float mu = dot(r, pSun);
    float mumu = mu * mu;
    float gg = g * g;
    float pRlh = 3.0 / (16.0 * PI) * (1.0 + mumu);
    float pMie = 3.0 / (8.0 * PI) * ((1.0 - gg) * (mumu + 1.0)) / (pow(1.0 + gg - 2.0 * mu * g, 1.5) * (2.0 + gg));

    for (int i = 0; i < iSteps; i++) {

        vec3 iPos = r0 + r * (iTime + iStepSize * 0.5);

        float iHeight = length(iPos) - rPlanet;

        float odStepRlh = exp(-iHeight / shRlh) * iStepSize;
        float odStepMie = exp(-iHeight / shMie) * iStepSize;

        iOdRlh += odStepRlh;
        iOdMie += odStepMie;

        float jStepSize = rsi(iPos, pSun, rAtmos).y / float(jSteps);

        float jTime = 0.0;

        float jOdRlh = 0.0;
        float jOdMie = 0.0;

        for (int j = 0; j < jSteps; j++) {

            vec3 jPos = iPos + pSun * (jTime + jStepSize * 0.5);

            float jHeight = length(jPos) - rPlanet;

            jOdRlh += exp(-jHeight / shRlh) * jStepSize;
            jOdMie += exp(-jHeight / shMie) * jStepSize;

            jTime += jStepSize;
        }

        vec3 attn = exp(-(kMie * (iOdMie + jOdMie) + kRlh * (iOdRlh + jOdRlh)));

        totalRlh += odStepRlh * attn;
        totalMie += odStepMie * attn;

        iTime += iStepSize;

    }

    return iSun * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
}

vec3 hash( vec3 x )
{
	x = vec3( dot(x,vec3(127.1,311.7, 74.7)),
			  dot(x,vec3(269.5,183.3,246.1)),
			  dot(x,vec3(113.5,271.9,124.6)));

	return fract(sin(x)*43758.5453123);
}

vec3 voronoi_sphere( in vec3 x )
{
    vec3 p = floor( x );  
    vec3 f = fract( x );  

    float sphere_radius = length(x);

	float id = 0.0;
    vec2 res = vec2( 100.0 );
    for( int k=-1; k<=1; k++ )
    for( int j=-1; j<=1; j++ )
    for( int i=-1; i<=1; i++ )
    {
        vec3 b = vec3( float(i), float(j), float(k) );  
        vec3 r = vec3( b ) - f + hash( p + b );         

        vec3 cell_center_in_os = p + b + vec3(0.5);
        float dist_between_cell_center_and_sphere_surface = abs(length(cell_center_in_os) - sphere_radius);

        float max_cell_dist = 0.5;
        if (dist_between_cell_center_and_sphere_surface < max_cell_dist)
        {

			vec3 r_in_os = x + r;
			r_in_os = normalize(r_in_os) * sphere_radius;
			r = r_in_os - x;

            float d = dot( r, r );
            if( d < res.x )
            {
                id = dot( p+b, vec3(1.0,57.0,113.0 ) );
                res = vec2( d, res.x );			
            }
            else if( d < res.y )
            {
                res.y = d;
            }
        }
    }

    return vec3( sqrt( res ), abs(id) );
}

void main() {
	vec3 rayDir = normalize(pos);

	vec3 sunDir = (lightDir * vec4(1, 0, 0, 1)).xyz;

	vec3 color = atmosphere(
        rayDir,
        vec3(0,0,6372e3 + altitude),               
        sunDir,                        
        22.0,                           
        6371e3,                         
        6471e3,                         
        vec3(5.5e-6, 13.0e-6, 22.4e-6), 
        21e-6,                          
        8e3,                            
        1.2e3,                          
        0.758                           
    );

	color += smoothstep(0.998, 0.999, dot(rayDir, sunDir)) * 20;

	fragColor = vec4(color, 1);

	float brightness = dot(color, vec3(0.2126, 0.7152, 0.0722));
	if (brightness < 0.02) {
		vec3 starColor = vec3(smoothstep(0.07, 0.05, voronoi_sphere((invLightDir * vec4(rayDir, 1)).xyz * 50).x));

		fragColor.rgb += (1 - 50 * brightness) * starColor;
	}

	fragColor.rgb = 1 - exp(-fragColor.rgb);
}