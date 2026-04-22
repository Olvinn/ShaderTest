#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

#define SSR_MAX_STEPS 64

float FresnelSchlickWater(float3 viewDir, float3 normal)
{
    const float R0 = 0.02;
    float cosTheta = saturate(abs(dot(-viewDir, normal)));
    return R0 + (1.0 - R0) * pow(1.0 - cosTheta, 5.0);
}

float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a      = roughness * roughness;
    float a2     = a * a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    return a2 / (PI * denom * denom);
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
    float3 F = FresnelSchlickWater(saturate(dot(normal, viewDir)), F0);
    float G = GeometrySmith(normal, viewDir, lightDir, roughness);

    float NdotL =  max(dot(normal, lightDir), 0.0);

    float3 specular = (D * F * G) / (4.0 * max(dot(normal, viewDir), 0.0) * NdotL + 0.001);

    return specular;
}

inline float2 SSR_ProjectVSPosToUV(float3 vsPos)
{
    float4 clip = mul(UNITY_MATRIX_P, float4(vsPos, 1.0));
    float2 uv   = clip.xy / max(clip.w, 1e-6);
    uv = uv * 0.5 + 0.5;
    #if UNITY_UV_STARTS_AT_TOP
    uv.y = 1.0 - uv.y;
    #endif
    return uv;
}

inline float SSR_SampleRawDepth(Texture2D depthTex, SamplerState samp, float2 uv)
{
    return SAMPLE_DEPTH_TEXTURE(depthTex, samp, uv);
}

float3 RaymarchSSR_ViewSpace(
    float3 originWS,
    float3 normalWS,
    int    steps,
    float  stepSize,
    float  thickness,
    float  stepPropagation,
    Texture2D opaque,
    SamplerState sampler_opaque,
    Texture2D depth,
    SamplerState sampler_depth,
    out bool hit)
{
    hit = false;
    if (steps <= 0) return 0;

    // View-space setup
    float3 originVS = mul(UNITY_MATRIX_V, float4(originWS, 1.0)).xyz;
    float3 viewDirVS = normalize(originVS);                               // towards camera
    float3 normalVS  = normalize(mul((float3x3)UNITY_MATRIX_V, normalWS)); // rotate normal to VS
    float3 reflDirVS = normalize(reflect(viewDirVS, normalVS));            // reflection dir in VS

    // Nudge off the surface a tiny bit to avoid self-intersection
    float  t = 1e-3; // meters
    float3 currVS = originVS + reflDirVS * t;

    int maxSteps = min(max(1, steps), SSR_MAX_STEPS);

    // Initialize previous dz at the starting point
    float2 uv = SSR_ProjectVSPosToUV(currVS);
    if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1) return 0;

    float rawDepth0 = SSR_SampleRawDepth(depth, sampler_depth, uv);
    if (rawDepth0 >= 0.9999) return 0;

    float sceneLinearZ0 = LinearEyeDepth(rawDepth0, _ZBufferParams);
    float currLinearZ0  = -currVS.z;                 // Unity VS: in front => negative z
    float prevDz = currLinearZ0 - sceneLinearZ0;     // <0 means ray point is in front of scene

    // March
    [loop]
    for (int i = 0; i < maxSteps; ++i)
    {
        // Depth-aware step so density is ~constant in screen space
        float depthScale = max(1.0, abs(currVS.z));
        float thisStep   = stepSize * depthScale * (stepPropagation * i);

        t     += thisStep;
        currVS = originVS + reflDirVS * t;

        uv = SSR_ProjectVSPosToUV(currVS);
        if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1) break;

        float rawDepth = SSR_SampleRawDepth(depth, sampler_depth, uv);
        if (rawDepth >= 0.9999) return 0; // hit sky

        float sceneLinearZ = LinearEyeDepth(rawDepth, _ZBufferParams);
        float currLinearZ  = -currVS.z;
        float dz           = currLinearZ - sceneLinearZ; // crossing when prevDz < 0 && dz >= 0

        if (dz >= 0 && prevDz < 0)
        {
            // --- refine the hit with a small binary search along the last segment ---
            float tLo = t - thisStep;
            float tHi = t;
            float bestT = tHi;

            [unroll(6)]
            for (int it = 0; it < 6; ++it)
            {
                float tMid = 0.5 * (tLo + tHi);
                float3 vsMid = originVS + reflDirVS * tMid;

                float2 uvMid = SSR_ProjectVSPosToUV(vsMid);
                float rawMid = SSR_SampleRawDepth(depth, sampler_depth, uvMid);
                if (rawMid >= 0.9999) { tHi = tMid; continue; }

                float sceneMid = LinearEyeDepth(rawMid, _ZBufferParams);
                float currMid  = -vsMid.z;
                float dzMid    = currMid - sceneMid;

                if (dzMid >= 0) { bestT = tMid; tHi = tMid; }
                else            { tLo = tMid; }
            }

            float3 vsHit = originVS + reflDirVS * bestT;
            float2 uvHit = SSR_ProjectVSPosToUV(vsHit);

            float rawHit   = SSR_SampleRawDepth(depth, sampler_depth, uvHit);
            float sceneHit = LinearEyeDepth(rawHit, _ZBufferParams);
            float currHit  = -vsHit.z;

            // Final thickness test in meters (view space)
            if (abs(currHit - sceneHit) <= thickness)
            {
                hit = true;
                return SAMPLE_TEXTURE2D(opaque, sampler_opaque, uvHit).rgb;
            }
        }

        prevDz = dz;
    }

    return 0;
}

inline float3 CubemapAmbient(float3 viewDir, float smooth)
{
    half4 encoded = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, viewDir, smooth);
    half3 skyColor = DecodeHDREnvironment(encoded, unity_SpecCube0_HDR);
    return skyColor;
}

inline float PhongDiffuse(float3 normal)
{
    Light light = GetMainLight();
    float pow = max(0, dot(float3(0, 1, 0), light.direction));
    return max(0, dot(normalize(light.direction), normal)) * pow;
}

inline float3 PhongSpecular(float3 viewDir, float3 normal, float power)
{
    Light light = GetMainLight();
    float3 h = normalize(light.direction + viewDir);
    float p = saturate(floor(dot(float3(0, 1, 0), light.direction)) + 1);
    return saturate(light.color * pow(max(0, dot(normal, h)), power) * p);
}
            
inline half3 Screen(half3 a, half3 b, half t)
{
    half3 s = 1.0h - (1.0h - a) * (1.0h - b);
    return lerp(a, s, t);
}

inline half3 Overlay(half3 a, half3 b, half t)
{
    half3 low  = 2.0h * a * b;
    half3 high = 1.0h - 2.0h * (1.0h - a) * (1.0h - b);
    half3 zeroOrOne = step(a, 0.5);
    half3 o = low * zeroOrOne + (1 - zeroOrOne) * high;
    return lerp(a, o, t);
}
            
inline half3 GetDepthTint(float3 posWS, float3 underWaterPosWS, half3 color, half4 shallowColor, half4 deepColor, half falloff)
{
    half depthDifWS = length(underWaterPosWS - posWS);
    half d = (falloff * .01);
    half shallow = saturate(depthDifWS / d);
    half deep = saturate((depthDifWS - d) / (falloff - d));
    shallowColor.rgb = Overlay(color, shallowColor.rgb, shallow * shallowColor.a);
    //return shallowColor;
    deepColor.rgb = lerp(color, deepColor.rgb, deep * deepColor.a);
    return lerp(shallowColor, deepColor, deep);
}