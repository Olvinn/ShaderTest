#include <UnityLightingCommon.cginc>
#include <UnityShaderVariables.cginc>
#include <UnityStandardUtils.cginc>

inline float SchlickFresnel(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

inline float3 Fresnel(float3 viewDir, float3 normal, float3 F0)
{
    float cosTheta = dot(viewDir, normal);
    
    cosTheta = clamp(cosTheta, 0.0, 1.0);

    return SchlickFresnel(cosTheta, F0);
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