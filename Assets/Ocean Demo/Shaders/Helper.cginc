#include <UnityLightingCommon.cginc>
#include <UnityShaderVariables.cginc>
#include <UnityStandardUtils.cginc>

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
    float3 N,          // Normal
    float3 V,          // View direction
    float3 L,          // Light direction
    float3 albedo,     // Base color
    float metallic,    // 0 = dielectric, 1 = metal
    float roughness    // 0 = smooth, 1 = rough
)
{
    float3 H = normalize(V + L);
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);

    float D =  DistributionGGX(N, H, roughness);
    float3 F = FresnelSchlick(saturate(dot(N, V)), F0);
    float G = GeometrySmith(N, V, L, roughness);

    float NdotL =  max(dot(N, L), 0.0);

    float3 specular = (D * F * G) / (4.0 * max(dot(N, V), 0.0) * NdotL + 0.001);

    return specular;
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

inline float3 GetFullNormal(sampler2D _Normal, float3 worldPos, float3 normal, float4 tangent, float power, float size)
{
    float3 tangentWS = normalize(tangent.xyz);
    float3 binormalWS = normalize(cross(normal, tangentWS)) * tangent.w;

    float3 normalTS = UnpackScaleNormal(tex2D(_Normal, worldPos.xz * size), 1.0);
    normalTS = normalize(float3(normalTS.x, normalTS.y / max(0.01, power), normalTS.z));

    float3x3 TBN = float3x3(tangentWS, binormalWS, normal);
    return normal;//normalize(mul(normalTS, TBN));
}