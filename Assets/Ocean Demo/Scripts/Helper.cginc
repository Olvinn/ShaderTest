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
    float p = max(0, normalize(dot(normal, _WorldSpaceLightPos0.xyz + float3(0, .03, 0))));
    // p=1;
    return saturate(_LightColor0 * pow(max(0, dot(normal, h)), power) * p);
}

inline float3 GetFullNormal(sampler2D _Normal, float3 worldPos, float3 normal, float4 tangent, float power, float size)
{
    float3 result = UnpackScaleNormal(tex2D(_Normal, worldPos.xz * size), 1);
    result = result.xzy;
    result.y /= power;
    float3 binormal = cross(normal, tangent.xyz) * tangent.w;
    result = normalize(
        result.x * tangent +
        result.y * normal +
        result.z * binormal
    );
    return result;
}