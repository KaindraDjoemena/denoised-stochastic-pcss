// denoiser.glsl

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

layout(location = 0) out vec4 u_DirResult;
layout(location = 1) out vec4 u_SpotResult;
layout(location = 2) out vec4 u_PointResult;

in vec2 TexCoords;

// G-Buffer
layout(binding = 1) uniform sampler2D gNormalMetal;
layout(binding = 2) uniform sampler2D gDepth;

// Shadow Masks
layout(binding = 10) uniform sampler2D u_DirShadowMask;
layout(binding = 11) uniform sampler2D u_SpotShadowMask;
layout(binding = 12) uniform sampler2D u_PointShadowMask;

// Filtering
uniform uint  u_Radius = 3;
uniform vec4  u_Direction;
uniform float u_SpatialSigma = 2.0;
uniform float u_NormalSigma  = 32.0;
uniform float u_DepthSigma   = 0.05;


float calcGaussian(float x, float sigma)
{
    return exp(-(x * x) / (2.0 * sigma * sigma));
}

void main() 
{
    vec2 u_Direction = u_Direction.xy;
    vec3 centerNormal = texture(gNormalMetal, TexCoords).rgb;
    float centerDepth = texture(gDepth, TexCoords).r;

    vec4 totalDenoisedDirShadowMask   = vec4(0.0);
    vec4 totalDenoisedSpotShadowMask  = vec4(0.0);
    vec4 totalDenoisedPointShadowMask = vec4(0.0);
    float wTotal = 0.0;

    for (int i = -int(u_Radius); i <= int(u_Radius); i++)
    {
        vec2 sampleUV = TexCoords + (float(i) * u_Direction);
        vec3 neighborNormal = texture(gNormalMetal, sampleUV).rgb;
        float neighborDepth = texture(gDepth, sampleUV).r;

        float wSpatial = calcGaussian(float(i), u_SpatialSigma);
        float normalDot = max(dot(centerNormal, neighborNormal), 0.0);
        float wNormal   = pow(normalDot, u_NormalSigma);
        float depthDiff = centerDepth - neighborDepth;
        float wDepth    = calcGaussian(depthDiff, u_DepthSigma);

        float w = wSpatial * wNormal * wDepth;

        totalDenoisedDirShadowMask   += texture(u_DirShadowMask, sampleUV) * w;
        totalDenoisedSpotShadowMask  += texture(u_SpotShadowMask, sampleUV) * w;
        totalDenoisedPointShadowMask += texture(u_PointShadowMask, sampleUV) * w;
        wTotal += w;
    }

    if (wTotal < 1e-5)
    {
        u_DirResult   = texture(u_DirShadowMask,   TexCoords);
        u_SpotResult  = texture(u_SpotShadowMask,  TexCoords);
        u_PointResult = texture(u_PointShadowMask, TexCoords);
    }
    else
    {
        u_DirResult   = totalDenoisedDirShadowMask   / wTotal;
        u_SpotResult  = totalDenoisedSpotShadowMask  / wTotal;
        u_PointResult = totalDenoisedPointShadowMask / wTotal;
    }
}