#include <UnityLightingCommon.cginc>
#include "UnityCG.cginc"

#define SSR_MAX_STEPS 64

float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a      = roughness * roughness;
    float a2     = a * a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    return a2 / (UNITY_PI * denom * denom);
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx1 = GeometrySchlickGGX(NdotV, roughness);
    float ggx2 = GeometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

float PBRSpecular(
    float3 normal,          
    float3 viewDir,         
    float3 lightDir,         
    float3 albedo,     
    float metallic,    
    float roughness    
)
{
    float3 H = normalize(viewDir + lightDir);
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);

    float D =  DistributionGGX(normal, H, roughness);
    float3 F = FresnelSchlick(saturate(dot(normal, viewDir)), F0);
    float G = GeometrySmith(normal, viewDir, lightDir, roughness);

    float NdotL =  max(dot(normal, lightDir), 0.0);

    float3 specular = (D * F * G) / (4.0 * max(dot(normal, viewDir), 0.0) * NdotL + 0.001);

    return specular;
}


float3 RaymarchSSR_ViewSpace(
    float3 originWS,
    float3 normalWS,
    int steps,
    float stepSize,
    float thickness,
    sampler2D depth,
    sampler2D lastFrame,
    out bool hit
)
{
    if (steps == 0) return 0;
                
    float3 originVS = mul(UNITY_MATRIX_V, float4(originWS, 1.0)).xyz;
    float3 viewDirVS = normalize(-originVS); 
    float3 normalVS = mul((float3x3)UNITY_MATRIX_V, normalWS);

    float3 reflDirVS = reflect(viewDirVS, normalVS);
    
    if (abs(dot(reflDirVS, viewDirVS)) > .85) return 0; //fix distant gliches

    float3 currVS = originVS + reflDirVS * 0.1;
    int maxSteps = min(max(1, steps), SSR_MAX_STEPS);

    for (int i = 0; i < maxSteps; i++)
    {
        float4 clipPos = mul(UNITY_MATRIX_P, float4(currVS, 1.0));
        float2 uv = (clipPos.xy / clipPos.w) * 0.5 + 0.5;

        #if UNITY_UV_STARTS_AT_TOP
        uv.y = 1.0 - uv.y;
        #endif

        if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1)
            break;

        float rawDepth = SAMPLE_DEPTH_TEXTURE(depth, uv);
        float sceneLinearZ = LinearEyeDepth(rawDepth);

        float dz = abs(-currVS.z - sceneLinearZ);
        if (dz < thickness)
        {
            hit = true;
            return tex2D(lastFrame, uv).rgb;
        }
        currVS += reflDirVS * stepSize;
    }
    return float3(0, 0, 0);
}

inline float3 CubemapAmbient(float3 viewDir, float3 normal, float smooth)
{
    float3 refl = reflect(-viewDir, normal);
    return UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, refl, smooth);
}

inline float PhongDiffuse(float3 normal)
{
    float3 lightDir = _WorldSpaceLightPos0.xyz;
    float pow = max(0, dot(float3(0, 1, 0), lightDir));
    return max(0, dot(normalize(lightDir), normal)) * pow;
}

inline float3 PhongSpecular(float3 viewDir, float3 normal, float power)
{
    float3 h = normalize(_WorldSpaceLightPos0.xyz + viewDir);
    float p = saturate(floor(dot(float3(0, 1, 0), _WorldSpaceLightPos0.xyz)) + 1);
    return saturate(_LightColor0 * pow(max(0, dot(normal, h)), power) * p);
}