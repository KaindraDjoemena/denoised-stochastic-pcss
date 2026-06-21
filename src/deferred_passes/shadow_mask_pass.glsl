// lighting_pass.glsl

#TYPE VERTEX
#version 460 core

out vec2 TexCoords;

void main() 
{
    float x = -1.0 + float((gl_VertexID & 1) << 2);
    float y = -1.0 + float((gl_VertexID & 2) << 1);
    
    TexCoords = vec2((x + 1.0) * 0.5, (y + 1.0) * 0.5);
    gl_Position = vec4(x, y, 0.0, 1.0);
}


#TYPE FRAGMENT
#version 460 core

layout(location = 0) out vec4 u_DirShadowMask;
layout(location = 1) out vec4 u_SpotShadowMask;
layout(location = 2) out vec4 u_PointShadowMask;

const float PI = 3.141592653589793;

// ===== Light Structs =====
struct DirLightData
{
    vec4 directionAndPower; // xyz = direction, w = power
    vec4 colorAndShadow;    // xyz = color,     w = shadow (-1 = no shadows)
};
struct PointLightData		
{
    vec4 positionAndRange; 	// xyz = position,               w = range
    vec4 colorAndPower;    	// xyz = color,                  w = power
    vec4 shadow;           	// x = shadow (-1 = no shadows), yzw = padding (0.0f)
};
struct SpotLightData		
{
    vec4 positionAndLength; // xyz = position,  w = length
    vec4 directionAndInner; // xyz = direction, w = innerCos
    vec4 colorAndOuter;     // xyz = color,     w = outerCos
    vec4 powerAndShadow;    // x = power,       y = shadow (-1.0f = no shadows), zw = padding (0.0f)
};


layout(std140, binding = 0) uniform CameraBuffer
{
    mat4 u_View;
    mat4 u_Projection;
    vec4 u_CameraPosAndTime;
};
layout(std430, binding = 2) readonly buffer LightBuffer
{
    uint u_DirCount;
    uint u_PointCount;
    uint u_SpotCount;
    uint u_Padding;
    
    DirLightData   u_DirLights[4];
    PointLightData u_PointLights[4];
    SpotLightData  u_SpotLights[4];
};

in vec2 TexCoords;

// G-Buffer
layout(binding = 1) uniform sampler2D gNormalMetal;
layout(binding = 2) uniform sampler2D gDepth;

// Shadow Maps
layout(binding = 10) uniform sampler2D   u_DirShadowMaps[4];
layout(binding = 14) uniform sampler2D   u_SpotShadowMaps[4];
layout(binding = 18) uniform samplerCube u_PointShadowMaps[4];

uniform mat4 u_InvView;
uniform mat4 u_InvProj;

uniform mat4 u_DirLightSpaceMat[4];
uniform mat4 u_SpotLightSpaceMat[4];


vec3 ReconstructWorldPos(vec2 uv, float depth);

const float MIN_BIAS = 0.00001;
const float MAX_BIAS = 0.001;
float calcDirShadow(sampler2D shadowMap, vec4 fragPosLightSpace, float bias);
float calcSpotShadow(sampler2D shadowMap, vec4 fragPosLightSpace, float bias);
float calcPointShadow(samplerCube shadowMap, vec3 fragPos, vec3 lightPos, float farPlane, float bias);

// PCSS
uniform float u_LightSize = 0.05;
const uint N_POISSON = 16;
const vec2 POISSON_DISK[N_POISSON] = vec2[] (
    vec2( 0.73697048, -0.3441632 ),
    vec2( 0.65462069,  0.29383535),
    vec2( 0.54072636, -0.93479401),
    vec2( 0.24053651, -0.32651431),
    vec2(-0.17461084, -0.61121731),
    vec2( 0.99094795, -0.93760053),
    vec2( 0.11646029,  0.37364405),
    vec2(-0.4037818 , -0.27219174),
    vec2(-0.35850971,  0.14422498),
    vec2(-0.72252853, -0.67943664),
    vec2(-0.82106902,  0.19321657),
    vec2(-0.84816692, -0.27373578),
    vec2(-0.79866493,  0.79232793),
    vec2(-0.26315799,  0.8757589 ),
    vec2( 0.44416786,  0.70974458),
    vec2( 0.92494026,  0.81237348));

float interleavedGradientNoise(vec2 screenPos);
float searchBlocker(sampler2D depthMap, vec4 fragPosLightSpace, float lightSize, float bias);
float searchBlocker(samplerCube depthMap, vec3 worldPos, vec3 lightPos, float farPlane, float lightSize, float bias);
float estimatePenumbraOrtho(vec4 fragPosLightSpace, float averageBlocked, float lightSize);
float estimatePenumbraPersp(vec4 fragPosLightSpace, float averageBlocked, float lightSize);
float estimatePenumbraPersp(float receiverDepth, float averageBlocked, float lightSize);
float pcf(sampler2D depthMap, vec4 fragPosLightSpace, float penumbraWidth, float bias);
float pcf(samplerCube depthMap, vec3 worldPos, vec3 lightPos, float farPlane, float penumbraWidth, float bias);


void main() 
{
    float depth = texture(gDepth, TexCoords).r;
    if (depth == 1.0)
        discard;

    u_DirShadowMask   = vec4(0.0);
    u_SpotShadowMask  = vec4(0.0);
    u_PointShadowMask = vec4(0.0);

    vec4 normalMetal = texture(gNormalMetal, TexCoords);

    vec3  N         = normalize(normalMetal.rgb);
    float METALLIC  = normalMetal.a;

    // World pos from depth
    vec3 worldPos = ReconstructWorldPos(TexCoords, depth);

    // Directional Lights
	for	(uint i = 0; i < u_DirCount; i++)
	{
		float shadow = 0.0;
		int shadowIdx = int(u_DirLights[i].colorAndShadow.w);

		if (shadowIdx >= 0)
		{
            vec4 fragPosLightSpace = u_DirLightSpaceMat[shadowIdx] * vec4(worldPos, 1.0);
			vec3 lightDir = normalize(-u_DirLights[i].directionAndPower.xyz);
			float dynamicBias = max(MAX_BIAS * (1.0 - dot(N, lightDir)), MIN_BIAS);

			shadow = calcDirShadow(u_DirShadowMaps[shadowIdx], fragPosLightSpace, dynamicBias);

            u_DirShadowMask[shadowIdx] = shadow;
		}
	}

    // Spot Ligts
	for (uint i = 0; i < u_SpotCount; i++)
	{
		float shadow = 0.0;
		int shadowIdx = int(u_SpotLights[i].powerAndShadow.y);

		if (shadowIdx >= 0)
		{
            vec4 fragPosLightSpace = u_SpotLightSpaceMat[shadowIdx] * vec4(worldPos, 1.0);
            vec3 lightDir = normalize(u_SpotLights[i].positionAndLength.xyz - worldPos);
			float dynamicBias = max(MAX_BIAS * (1.0 - dot(N, lightDir)), MIN_BIAS);

			shadow = calcSpotShadow(u_SpotShadowMaps[shadowIdx], fragPosLightSpace, dynamicBias);

            u_SpotShadowMask[shadowIdx] = shadow;
		}
	}

	// Point Lights Loop
	for (uint i = 0; i < u_PointCount; i++)
	{
		float shadow = 0.0;
		int shadowIdx = int(u_PointLights[i].shadow.x);

		if (shadowIdx >= 0)
        {
			vec3 lightDir = normalize(u_PointLights[i].positionAndRange.xyz - worldPos);
			float dynamicBias = max(MAX_BIAS * (1.0 - dot(N, lightDir)), MIN_BIAS);
		
			float lightRange = u_PointLights[i].positionAndRange.w;
			shadow = calcPointShadow(u_PointShadowMaps[shadowIdx], worldPos, u_PointLights[i].positionAndRange.xyz, lightRange, dynamicBias);
		
            u_PointShadowMask[shadowIdx] = shadow;
        }
	}
}


vec3 ReconstructWorldPos(vec2 uv, float depth)
{
    float z = depth * 2.0 - 1.0;
    vec4 clipSpacePos = vec4(uv * 2.0 - 1.0, z, 1.0);
    
    vec4 viewSpacePos = u_InvProj * clipSpacePos;
    viewSpacePos /= viewSpacePos.w;
    
    vec4 worldSpacePos = u_InvView * viewSpacePos;
    
    return worldSpacePos.xyz;
}


// ===== SHADOW CALC =====
float calcDirShadow(sampler2D shadowMap, vec4 fragPosLightSpace, float bias)
{
    float blockerDepth = searchBlocker(shadowMap, fragPosLightSpace, u_LightSize, bias);
	
    if (blockerDepth < 0.0)
        return 0.0;
	
    float penumbra = estimatePenumbraOrtho(fragPosLightSpace, blockerDepth, u_LightSize);

    return pcf(shadowMap, fragPosLightSpace, penumbra, bias);
}

float calcSpotShadow(sampler2D shadowMap, vec4 fragPosLightSpace, float bias)
{
    float blockerDepth = searchBlocker(shadowMap, fragPosLightSpace, u_LightSize, bias);
	
    if (blockerDepth < 0.0)
        return 0.0;
	
    float penumbra = estimatePenumbraPersp(fragPosLightSpace, blockerDepth, u_LightSize);

    return pcf(shadowMap, fragPosLightSpace, penumbra, bias);
}

float calcPointShadow(samplerCube shadowMap, vec3 fragPos, vec3 lightPos, float farPlane, float bias)
{
    float blockerDepth = searchBlocker(shadowMap, fragPos, lightPos, farPlane, u_LightSize, bias);

    if (blockerDepth < 0.0)
        return 0.0;

    float receiverDepth = length(fragPos - lightPos);
    float penumbra = estimatePenumbraPersp(receiverDepth, blockerDepth, u_LightSize);

    return pcf(shadowMap, fragPos, lightPos, farPlane, penumbra, bias);
}

// 1D low discrepancy function
float interleavedGradientNoise(vec2 screenPos)
{
    vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(screenPos, magic.xy)));
}

// ===== BLOCKER SEARCH =====
float searchBlocker(sampler2D depthMap, vec4 fragPosLightSpace, float lightSize, float bias)
{
    vec3 projCoords = fragPosLightSpace.xyz / fragPosLightSpace.w;
    projCoords = projCoords * 0.5 + 0.5;
    if (projCoords.z > 1.0)
        return -1.0;

    float angle = interleavedGradientNoise(gl_FragCoord.xy) * PI * 2.0;
    float s = sin(angle);
    float c = cos(angle);
    mat2 rot = mat2(c, -s, s, c);

    float totalBlocked = 0.0;
    int numBlockers = 0;
    for (int i = 0; i < N_POISSON; i++)
    {
        vec2 rotatedOffset = rot * POISSON_DISK[i];
        vec2 samplePoint = projCoords.xy + (rotatedOffset * lightSize);

        float currentDepth = texture(depthMap, samplePoint).r;

        if (projCoords.z - bias > currentDepth)
        {
            totalBlocked += currentDepth;
            numBlockers++;
        }
    }

    if (numBlockers < 1)
        return -1.0;

    return totalBlocked / float(numBlockers);
}

float searchBlocker(samplerCube depthMap, vec3 worldPos, vec3 lightPos, float farPlane, float lightSize, float bias)
{
    vec3 fragToLight = worldPos - lightPos;
    vec3 lightDir = normalize(fragToLight);

    // Tangent space
    vec3 up = abs(lightDir.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 right = normalize(cross(up, lightDir));
    up = cross(lightDir, right);

    float angle = interleavedGradientNoise(gl_FragCoord.xy) * PI * 2.0;
    float s = sin(angle);
    float c = cos(angle);
    mat2 rot = mat2(c, -s, s, c);

    float totalBlocked = 0.0;
    int numBlockers = 0;
    for (int i = 0; i < N_POISSON; i++)
    {
        vec2 rotatedOffset = rot * POISSON_DISK[i];
        vec3 sampleDir = lightDir + (right * rotatedOffset.x * lightSize) + (up * rotatedOffset.y * lightSize);

        float currentDepth = texture(depthMap, sampleDir).r * farPlane;

        if (length(fragToLight) - bias > currentDepth)
        {
            totalBlocked += currentDepth;
            numBlockers++;
        }
    }

    if (numBlockers < 1)
        return -1.0;

    return totalBlocked / float(numBlockers);
}

// ===== PENUMBRA ESTIMATION =====
float estimatePenumbraPersp(vec4 fragPosLightSpace, float averageBlocked, float lightSize)
{
    vec3 projCoords = fragPosLightSpace.xyz / fragPosLightSpace.w;
    projCoords = projCoords * 0.5 + 0.5;

    // w_penumbra = (d_receiver - d_blocker) * w_light / d_blocker
    float wPenumbra = (projCoords.z - averageBlocked) * lightSize / averageBlocked;

    return wPenumbra;
}

float estimatePenumbraPersp(float receiverDepth, float averageBlocked, float lightSize)
{
    // w_penumbra = (d_receiver - d_blocker) * w_light / d_blocker
    float wPenumbra = (receiverDepth - averageBlocked) * lightSize / averageBlocked;

    return wPenumbra;
}

float estimatePenumbraOrtho(vec4 fragPosLightSpace, float averageBlocked, float lightSize)
{
    vec3 projCoords = fragPosLightSpace.xyz / fragPosLightSpace.w;
    projCoords = projCoords * 0.5 + 0.5;

    // w_penumbra = (d_receiver - d_blocker) * w_light
    float wPenumbra = (projCoords.z - averageBlocked) * lightSize;

    return wPenumbra;
}

// ===== PCF CALC =====
float pcf(sampler2D depthMap, vec4 fragPosLightSpace, float penumbraWidth, float bias)
{
    vec3 projCoords = fragPosLightSpace.xyz / fragPosLightSpace.w;
    projCoords = projCoords * 0.5 + 0.5;
    if (projCoords.z > 1.0)
        return -1.0;

    float angle = interleavedGradientNoise(gl_FragCoord.xy) * PI * 2.0;
    float s = sin(angle);
    float c = cos(angle);
    mat2 rot = mat2(c, -s, s, c);

    float shadow = 0.0;
    for (int i = 0; i < N_POISSON; i++)
    {
        vec2 rotatedOffset = rot * POISSON_DISK[i];
        vec2 samplePoint = projCoords.xy + (rotatedOffset * penumbraWidth);

        float currentDepth = texture(depthMap, samplePoint).r;

        if (projCoords.z - bias > currentDepth)
            shadow += 1.0;
    }

    return shadow / float(N_POISSON);
}

float pcf(samplerCube depthMap, vec3 worldPos, vec3 lightPos, float farPlane, float penumbraWidth, float bias)
{
    vec3 fragToLight = worldPos - lightPos;
    vec3 lightDir = normalize(fragToLight);
    float receiverDepth = length(fragToLight);

    // Tangent Space
    vec3 up = abs(lightDir.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 right = normalize(cross(up, lightDir));
    up = cross(lightDir, right);

    float angle = interleavedGradientNoise(gl_FragCoord.xy) * PI * 2.0;
    float s = sin(angle);
    float c = cos(angle);
    mat2 rot = mat2(c, -s, s, c);

    float shadow = 0.0;
    for (int i = 0; i < N_POISSON; i++)
    {
        vec2 rotatedOffset = rot * POISSON_DISK[i];
        vec3 sampleDir = lightDir + (right * rotatedOffset.x * penumbraWidth) + (up * rotatedOffset.y * penumbraWidth);

        float currentDepth = texture(depthMap, sampleDir).r * farPlane;

        if (receiverDepth - bias > currentDepth)
            shadow += 1.0;
    }

    return shadow / float(N_POISSON);
}