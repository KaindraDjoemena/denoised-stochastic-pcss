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

out vec4 FragColor;

// G-Buffer
layout(binding = 0) uniform sampler2D gAlbedoRough;
layout(binding = 1) uniform sampler2D gNormalMetal;
layout(binding = 2) uniform sampler2D gDepth;

// IBL Maps
layout(binding = 5) uniform samplerCube u_IrradianceMap;
layout(binding = 6) uniform samplerCube u_PrefilterMap;
layout(binding = 7) uniform sampler2D   u_BrdfLut;

// Shadow Masks
layout(binding = 10) uniform sampler2D u_RawDirShadowMask;
layout(binding = 11) uniform sampler2D u_RawSpotShadowMask;
layout(binding = 12) uniform sampler2D u_RawPointShadowMask;

// Denoised Masks
layout(binding = 13) uniform sampler2D u_DenoisedDirShadowMask;
layout(binding = 14) uniform sampler2D u_DenoisedSpotShadowMask;
layout(binding = 15) uniform sampler2D u_DenoisedPointShadowMask;

uniform float u_SplitX = 0.5;

uniform mat4 u_InvView;
uniform mat4 u_InvProj;


vec3 ReconstructWorldPos(vec2 uv, float depth);

float NDF_GGXTR(vec3 N, vec3 H, float roughness);
float G_SchlickGGX(float NdotV, float roughness);
float G_Smith(vec3 N, vec3 V, vec3 L, float roughness);
vec3 F_Schlick(float cosTheta, vec3 F0);
vec3 F_SchlickR(float cosTheta, vec3 F0, float roughness);

vec3 calcDirLight(DirLightData light, vec3 N, vec3 V, float shadow, vec3 ALBEDO, float ROUGHNESS, float METALLIC, vec3 F0);
vec3 calcSpotLight(SpotLightData light, vec3 N, vec3 V, vec3 fragPos, float shadow, vec3 ALBEDO, float ROUGHNESS, float METALLIC, vec3 F0);
vec3 calcPointLight(PointLightData light, vec3 N, vec3 V, vec3 fragPos, float shadow, vec3 ALBEDO, float ROUGHNESS, float METALLIC, vec3 F0);


void main() 
{
    float depth = texture(gDepth, TexCoords).r;
    if (depth == 1.0)
        discard;


    vec4 albedoRough = texture(gAlbedoRough, TexCoords);
    vec4 normalMetal = texture(gNormalMetal, TexCoords);

    vec3  ALBEDO    = albedoRough.rgb;
    float ROUGHNESS = albedoRough.a;
    vec3  N         = normalize(normalMetal.rgb);
    float METALLIC  = normalMetal.a;

    ROUGHNESS = clamp(ROUGHNESS, 0.03, 1.0);  // prevent infinitely small specular points

    // World pos from depth
    vec3 worldPos = ReconstructWorldPos(TexCoords, depth);
	vec3 V = normalize(u_CameraPosAndTime.xyz - worldPos);

	vec3 F0 = vec3(0.04);
	F0 = mix(F0, ALBEDO, METALLIC);
	
	vec3 Lo = vec3(0.0);

    // Directional Lights
	for	(uint i = 0; i < u_DirCount; i++)
	{
		float shadow = 0.0;
		int shadowIdx = int(u_DirLights[i].colorAndShadow.w);

		if (shadowIdx >= 0)
		{
            if (TexCoords.x < u_SplitX)
            {
                shadow = texture(u_DenoisedDirShadowMask, TexCoords)[shadowIdx];
            }
            else
            {
                shadow = texture(u_RawDirShadowMask, TexCoords)[shadowIdx];
            }
		}
	
		Lo += calcDirLight(u_DirLights[i], N, V, shadow, ALBEDO, ROUGHNESS, METALLIC, F0);
	}

    // Spot Ligts
	for (uint i = 0; i < u_SpotCount; i++)
	{
		float shadow = 0.0;
		int shadowIdx = int(u_SpotLights[i].powerAndShadow.y);

		if (shadowIdx >= 0)
		{
            if (TexCoords.x < u_SplitX)
            {
                shadow = texture(u_DenoisedSpotShadowMask, TexCoords)[shadowIdx];
            }
            else
            {
                shadow = texture(u_RawSpotShadowMask, TexCoords)[shadowIdx];
            }
		}
		
		Lo += calcSpotLight(u_SpotLights[i], N, V, worldPos, shadow, ALBEDO, ROUGHNESS, METALLIC, F0);
	}

	// Point Lights Loop
	for (uint i = 0; i < u_PointCount; i++)
	{
		float shadow = 0.0;
		int shadowIdx = int(u_PointLights[i].shadow.x);

		if (shadowIdx >= 0)
        {
            if (TexCoords.x < u_SplitX)
            {
                shadow = texture(u_DenoisedPointShadowMask, TexCoords)[shadowIdx];
            }
            else
            {
                shadow = texture(u_RawPointShadowMask, TexCoords)[shadowIdx];
            }
		}

		Lo += calcPointLight(u_PointLights[i], N, V, worldPos, shadow, ALBEDO, ROUGHNESS, METALLIC, F0);
	}

	// IBL Ambient Lighting
	vec3 F = F_SchlickR(max(dot(N, V), 0.0), F0, ROUGHNESS);
    vec3 kS = F;
    vec3 kD = 1.0 - kS;
    kD *= 1.0 - METALLIC;

	// Diffuse IBL
	vec3 irradiance = texture(u_IrradianceMap, N).rgb;
	vec3 diffuse = irradiance * ALBEDO;

	// Specular IBL
    vec3 R = reflect(-V, N); 
    const float MAX_REFLECTION_LOD = 4.0;
    vec3 prefilteredColor = textureLod(u_PrefilterMap, R, ROUGHNESS * MAX_REFLECTION_LOD).rgb;
    vec2 envBRDF = texture(u_BrdfLut, vec2(max(dot(N, V), 0.0), ROUGHNESS)).rg;
    vec3 specular = prefilteredColor * (F0 * envBRDF.x + envBRDF.y);

    vec3 ambient = (kD * diffuse + specular); 

	FragColor = vec4(ambient + Lo, 1.0);
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


vec3 calcDirLight(DirLightData light, vec3 N, vec3 V, float shadow, vec3 ALBEDO, float ROUGHNESS, float METALLIC, vec3 F0)
{
    vec3 L = normalize(-light.directionAndPower.xyz);
    vec3 H = normalize(V + L);
    vec3 radiance = light.colorAndShadow.rgb * light.directionAndPower.w;
    
    float NDF = NDF_GGXTR(N, H, ROUGHNESS);   
    float G   = G_Smith(N, V, L, ROUGHNESS);
	vec3  F   = F_SchlickR(max(dot(N, V), 0.0), F0, ROUGHNESS);
    
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - METALLIC;	  
    
    vec3 numerator    = NDF * G * F; 
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001; 
    vec3 specular     = numerator / denominator;
    float NdotL = max(dot(N, L), 0.0);
    
    return (kD * ALBEDO / PI + specular) * radiance * NdotL * (1.0 - shadow);
}

vec3 calcSpotLight(SpotLightData light, vec3 N, vec3 V, vec3 fragPos, float shadow, vec3 ALBEDO, float ROUGHNESS, float METALLIC, vec3 F0)
{
    vec3 L = normalize(light.positionAndLength.xyz - fragPos);
    vec3 H = normalize(V + L);
    
	float dist = length(light.positionAndLength.xyz - fragPos);
	float distRatio = dist / light.positionAndLength.w;
	float falloff = clamp(1.0 - (distRatio * distRatio * distRatio * distRatio), 0.0, 1.0);
	
	float attenuation = (falloff * falloff) / (dist * dist + 1.0);
	
    float theta = dot(L, normalize(-light.directionAndInner.xyz)); 
    float epsilon = light.directionAndInner.w - light.colorAndOuter.w; 
    float intensity = clamp((theta - light.colorAndOuter.w) / epsilon, 0.0, 1.0); 
    
    vec3 radiance = light.colorAndOuter.rgb * light.powerAndShadow.x * attenuation * intensity;
    
    float NDF = NDF_GGXTR(N, H, ROUGHNESS);   
    float G   = G_Smith(N, V, L, ROUGHNESS);      
    vec3  F   = F_SchlickR(max(dot(H, V), 0.0), F0, ROUGHNESS);
    
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - METALLIC;	  
    
    vec3 numerator    = NDF * G * F; 
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001; 
    vec3 specular     = numerator / denominator;
    float NdotL = max(dot(N, L), 0.0);
    
    return (kD * ALBEDO / PI + specular) * radiance * NdotL * (1.0 - shadow);
}

vec3 calcPointLight(PointLightData light, vec3 N, vec3 V, vec3 fragPos, float shadow, vec3 ALBEDO, float ROUGHNESS, float METALLIC, vec3 F0)
{
    vec3 L = normalize(light.positionAndRange.xyz - fragPos);
    vec3 H = normalize(V + L);
    
	float dist = length(light.positionAndRange.xyz - fragPos);
	float distRatio = dist / light.positionAndRange.w;
	float falloff = clamp(1.0 - (distRatio * distRatio * distRatio * distRatio), 0.0, 1.0);
	
	float attenuation = (falloff * falloff) / (dist * dist + 1.0);

    vec3 radiance = light.colorAndPower.rgb * light.colorAndPower.w * attenuation;

    float NDF = NDF_GGXTR(N, H, ROUGHNESS);   
    float G   = G_Smith(N, V, L, ROUGHNESS);      
    vec3  F   = F_SchlickR(max(dot(H, V), 0.0), F0, ROUGHNESS);
    
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - METALLIC;	  
    
    vec3 numerator    = NDF * G * F; 
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001; 
    vec3 specular     = numerator / denominator;
    float NdotL = max(dot(N, L), 0.0);
    
    return (kD * ALBEDO / PI + specular) * radiance * NdotL * (1.0 - shadow);
}


float NDF_GGXTR(vec3 N, vec3 H, float roughness)
{
    float a  = roughness * roughness; float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0); float NdotH2 = NdotH * NdotH;
    float nom   = a2; float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    return nom / (PI * denom * denom);
}

float G_SchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0); float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float G_Smith(vec3 N, vec3 V, vec3 L, float roughness)
{
    return G_SchlickGGX(max(dot(N, V), 0.0), roughness) * G_SchlickGGX(max(dot(N, L), 0.0), roughness);
}

vec3 F_Schlick(float cosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

vec3 F_SchlickR(float cosTheta, vec3 F0, float roughness)
{
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}