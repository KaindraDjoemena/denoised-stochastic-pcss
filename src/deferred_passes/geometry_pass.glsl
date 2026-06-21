// geometry_pass.glsl

#TYPE VERTEX
#version 460 core

layout (location = 0) in vec3 a_Pos;
layout (location = 1) in vec3 a_Normal;
layout (location = 2) in vec2 a_TexCoords;


// ===== Instance Mats =====
struct InstanceData
{
    mat4 model;
    mat4 normal;
};


layout(std140, binding = 0) uniform CameraBuffer
{
    mat4 u_View;
    mat4 u_Projection;
    vec4 u_CameraPosAndTime;
};
layout(std430, binding = 1) readonly buffer InstanceBuffer
{
    InstanceData u_Instances[];
};

uniform uint u_TransformIndex;

// ===== VERTEX SHADER OUT =====
out VS_OUT {
    vec3 v_FragPos;
    vec3 v_Normal;
    vec2 v_TexCoords;
} vs_out;


void main() 
{
    mat4 modelMat  = u_Instances[u_TransformIndex].model;
    mat3 normalMat = mat3(u_Instances[u_TransformIndex].normal);

	vs_out.v_FragPos   	 	   = vec3(modelMat * vec4(a_Pos, 1));
    vs_out.v_Normal    		   = normalMat * a_Normal;
	vs_out.v_TexCoords 		   = a_TexCoords;
    
	gl_Position = u_Projection * u_View * modelMat * vec4(a_Pos, 1.0);		// world space transformation
}


#TYPE FRAGMENT
#version 460 core

layout(location = 0) out vec4 gAlbedoRoughness;
layout(location = 1) out vec4 gNormalMetallic;

layout(std140, binding = 0) uniform CameraBuffer
{
    mat4 u_View;
    mat4 u_Projection;
    vec4 u_CameraPosAndTime;
};

in VS_OUT {
    vec3 v_FragPos;
    vec3 v_Normal;
    vec2 v_TexCoords;
} fs_in;

layout(binding = 0) uniform sampler2D u_albedoMap;     uniform bool u_hasAlbedoMap;     uniform vec3  u_albedoFactor;
layout(binding = 1) uniform sampler2D u_normalMap;	   uniform bool u_hasNormalMap;
layout(binding = 2) uniform sampler2D u_metallicMap;   uniform bool u_hasMetallicMap;   uniform float u_metallicFactor;
layout(binding = 3) uniform sampler2D u_roughnessMap;  uniform bool u_hasRoughnessMap;  uniform float u_roughnessFactor;
layout(binding = 4) uniform sampler2D u_aoMap;		   uniform bool u_hasAOMap;		    uniform float u_AOFactor;


vec3 getNormalFromMap();


void main() 
{
	vec3  ALBEDO    = u_hasAlbedoMap ? pow(texture(u_albedoMap, fs_in.v_TexCoords).rgb, vec3(2.2)) : u_albedoFactor;
    vec3  NORMAL    = u_hasNormalMap ? getNormalFromMap() : normalize(fs_in.v_Normal);
    float METALLIC  = u_hasMetallicMap ? texture(u_metallicMap, fs_in.v_TexCoords).b : u_metallicFactor;		// Blue channel
    float ROUGHNESS = u_hasRoughnessMap ? texture(u_roughnessMap, fs_in.v_TexCoords).g : u_roughnessFactor;		// Green channel
    float AO        = u_hasAOMap ? texture(u_aoMap, fs_in.v_TexCoords).r : u_AOFactor;							// Red channel

    gAlbedoRoughness = vec4(ALBEDO, ROUGHNESS);
    gNormalMetallic = vec4(NORMAL, METALLIC);
}


vec3 getNormalFromMap()
{
    vec3 tangentNormal = texture(u_normalMap, fs_in.v_TexCoords).xyz * 2.0 - 1.0;

    vec3 Q1  = dFdx(fs_in.v_FragPos);
    vec3 Q2  = dFdy(fs_in.v_FragPos);
    vec2 st1 = dFdx(fs_in.v_TexCoords);
    vec2 st2 = dFdy(fs_in.v_TexCoords);

    vec3 N   = normalize(fs_in.v_Normal);
    vec3 T   = normalize(Q1 * st2.t - Q2 * st1.t);
    vec3 B   = -normalize(cross(N, T));
    mat3 TBN = mat3(T, B, N);

    return normalize(TBN * tangentNormal);
}