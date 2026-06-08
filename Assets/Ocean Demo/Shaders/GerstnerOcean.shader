Shader "Custom/GerstnerOcean"
{
    Properties
    {
        _NormalMap ("Normal map", 2D) = "white" {}
        _NormalsPower ("Normals power", Range(0,1)) = .5
        
        [Header(Water Volume)]
        _WaterAbsorption ("Absorption (rgb = per channel)", Color) = (0.45, 0.06, 0.01, 0)
        _WaterScatter    ("Scatter (rgb = per channel)",    Color) = (0.02, 0.05, 0.08, 0)
        
        _Transparency   ("Transparency",    Range(0, 1000))    = 0
        _MaxWaves       ("Max Waves",       Range(1, 128))   = 64
        _FoamTexture    ("Foam Texture",    2D)             = "white" {}
        _FoamAmount     ("Foam Amount",     Float)          = 1
        _FoamStrength   ("Foam Strength",   Float)          = 1
        _Metallic       ("Metallic",        Range(0, 1))    = 0.5
        _Roughness      ("Roughness",       Range(0, 1))    = 0.5

        [Header(SSR)]
        _SSRSteps           ("Steps",          Integer)        = 32
        _SSRStepSize        ("Step Size",       Range(0.01, 5)) = 0.5
        _StepPropagation    ("Propagation",     Range(0, 1))    = 0.01
        _SSRThickness       ("Thickness",       Range(0.01, 1)) = 0.5
        
        [Header(SSS)]
        _SSSStrength        ("Strength",        Range(0, 2))    = 0.8
        _SSSDirectionality  ("Directionality",  Range(1, 8))    = 4.0
        _SSSThicknessPower  ("Thickness Power", Range(0.1, 4))  = 2.0
        _SSSAmbient         ("Ambient",         Range(0, 1))  = 0.1
        _MaxWaveAmplitude   ("Max Amplitude",   Float)          = 1.5
        
        [Toggle] _FogBlend  ("Blend in Fog", Int) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType"     = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "RenderQueue"    = "Transparent"
        }

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }

            Cull Off

            HLSLPROGRAM
            #pragma target 5.0
            #pragma vertex   vert
            #pragma fragment frag

            #pragma multi_compile_fog
            #pragma shader_feature SSR

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING  
            #pragma multi_compile _ SHADOWS_SHADOWMASK      

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "Helper.cginc"
            #include "Gerstner.cginc"

            // ── Textures ─────────────────────────────────────────
            TEXTURE2D_X(_FoamTexture);              SAMPLER(sampler_FoamTexture);
            TEXTURE2D_X(_NormalMap);                SAMPLER(sampler_NormalMap);
            TEXTURE2D(_LocalWaterDetails);          SAMPLER(sampler_LocalWaterDetails);
            TEXTURE2D_X(_CameraOpaqueTexture);      SAMPLER(sampler_CameraOpaqueTexture);
            TEXTURE2D_X_FLOAT(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);

            // ── Constant buffer ───────────────────────────────────
            CBUFFER_START(UnityPerMaterial)
                float4 _WaterAbsorption, _WaterScatter, _FoamTexture_ST;
                float4 _MapCenterWS, _MapSizeWS;
                half   _FoamAmount, _FoamStrength, _Transparency, _NormalsPower;
                half   _Metallic, _Roughness;
                int    _MaxWaves, _FogBlend;
                #ifdef SSR
                    half _SSRThickness, _SSRStepSize, _StepPropagation;
                    int  _SSRSteps;
                #endif
                half  _SSSStrength, _SSSDirectionality, _SSSThicknessPower, _SSSAmbient;
                float _MaxWaveAmplitude;
            CBUFFER_END

            #define MAX_WAVES       128
            #define SSR_MAX_STEPS   64
            #define IOR_AIR_WATER   0.75 

            struct Attributes
            {
                float4 vertex : POSITION;
                half2  uv     : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float  fog        : TEXCOORD1; 
                float4 positionSS : TEXCOORD2;
                float3 initialWS  : TEXCOORD3;
                float2 uv         : TEXCOORD4;
                float3 normalWS   : TEXCOORD5;
                float3 tangentWS  : TEXCOORD6;
                float3 bitangentWS: TEXCOORD7;
            };

            float3 ReadDetailsHeight(float2 worldXZ)
            {
                float2 uv = (worldXZ - _MapCenterWS.xz) / _MapSizeWS.xz + 0.5;
                float4 packed = SAMPLE_TEXTURE2D_LOD(_LocalWaterDetails,
                                                  sampler_LocalWaterDetails, uv, 0);
                return packed.b;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;

                float3 worldPos = mul(unity_ObjectToWorld, float4(IN.vertex.xyz, 1)).xyz;
                OUT.initialWS = worldPos;

                float3 normal, tangent;
                
                float3 offset = Gerstner_GetOffset(worldPos.xz, _Time.y, _MaxWaves, normal, tangent);
                worldPos += offset;
                worldPos.y += ReadDetailsHeight(worldPos.xz);

                float4 clipPos    = TransformWorldToHClip(worldPos);
                OUT.positionCS    = clipPos;
                OUT.positionSS    = ComputeScreenPos(clipPos);
                OUT.positionWS    = worldPos;
                OUT.uv            = IN.uv;
                OUT.fog           = ComputeFogFactor(clipPos.z);
                OUT.normalWS      = normalize(normal);
                OUT.tangentWS     = normalize(tangent);
                OUT.bitangentWS   = cross(OUT.normalWS, OUT.tangentWS);

                return OUT;
            }

            float3 ReadDetailsNormal(float2 worldXZ)
            {
                float2 uv = (worldXZ - _MapCenterWS.xz) / _MapSizeWS.xz + 0.5;
                float4 packed = SAMPLE_TEXTURE2D(_LocalWaterDetails,
                                                  sampler_LocalWaterDetails, uv);
                return normalize(float3(-packed.r, 1.0, -packed.g));
            }

            float ReadFoam(float2 worldXZ)
            {
                float2 uv = (worldXZ - _MapCenterWS.xz) / _MapSizeWS.xz + 0.5;
                float foam = SAMPLE_TEXTURE2D(_LocalWaterDetails,
                                                  sampler_LocalWaterDetails, uv).a;
                return foam;
            }

            float HenyeyGreenstein(float cosTheta, float g)
            {
                float g2 = g * g;
                float d  = 1.0 + g2 - 2.0 * g * cosTheta;
                return (1.0 - g2) / (4.0 * PI * pow(d, 1.5));
            }

            half3 WaterSSS(float3 viewDir, float3 normal, Light light,
               float jacobian, float waveDisplacement)
            {
                float3 sigmaA = _WaterAbsorption.rgb;
                float3 sigmaS = _WaterScatter.rgb;
                float3 sigmaT = sigmaA + sigmaS;

                float jacobianThin = saturate(1.5 - jacobian);
                float heightThin   = saturate(waveDisplacement / max(_MaxWaveAmplitude, 0.001));
                float thickness    = pow(saturate(max(jacobianThin, heightThin)),
                                         _SSSThicknessPower);

                float NdotL    = dot(normal, light.direction);
                float NdotV    = dot(normal, viewDir);
                float optDepth = thickness * (1.0 / max(NdotL, 0.1)
                                            + 1.0 / max(NdotV, 0.1));
                optDepth       = min(optDepth, _SSSAmbient);

                float3 transmit = exp(-sigmaT * optDepth);

                float  phase      = HenyeyGreenstein(dot(light.direction, viewDir), 0.5);
                float3 volScatter = light.color * sigmaS * phase
                                  * (1.0 - transmit) / max(sigmaT, 0.0001);

                float  VdotL       = dot(-viewDir, light.direction);
                float  backLobe    = pow(saturate(NdotL * VdotL), _SSSDirectionality);
                float3 backScatter = backLobe * thickness * -NdotV
                                   * sigmaS / max(sigmaT, 0.0001)
                                   * light.color * .05;

                float  crestMask  = saturate(heightThin * jacobianThin * 1.0) * max(0, -VdotL) * max(0, NdotV * .5 + .5) * 2;
                float3 crestBoost = crestMask * light.color
                                  * sigmaS / max(sigmaT, 0.0001) * 0.4;

                float shadow = 1;//max(light.shadowAttenuation, .5);

                return (volScatter + backScatter + crestBoost)
                     * _SSSStrength
                     * shadow;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3x3 TBN    = float3x3(i.tangentWS, i.bitangentWS, i.normalWS);
                float3 normal   = i.normalWS;//normalize(mul(ReadDetailsNormal(i.initialWS.xz), TBN));
                float4 packed1 = SAMPLE_TEXTURE2D(_NormalMap,
                                                  sampler_NormalMap, i.initialWS.xz * .1);
                float4 packed2 = SAMPLE_TEXTURE2D(_NormalMap,
                                                  sampler_NormalMap, i.initialWS.xz * .15 - _Time.y * .15);
                float3 normalTS = lerp(UnpackNormal(packed1), UnpackNormal(packed2), .5);
                float  jacobian = 0;
                jacobian = max(jacobian, ReadFoam(i.initialWS.xz));
                normalTS.xy *= saturate(.85 - jacobian * 1.25) * _NormalsPower * .5 + .05;
                normalTS = normalize(normalTS);
                normal = normalize(mul(normalTS, TBN));
                //Gerstner_GetNormalJacobian(i.initialWS.xz, _Time.y, 32, normal, jacobian);

                float3 viewDir  = normalize(i.positionWS - _WorldSpaceCameraPos);
                float3 reflDir  = reflect(viewDir, normal);
                float3 refrDir  = refract(viewDir, normal, IOR_AIR_WATER);

                float4 shadowCoord;
                #ifdef _MAIN_LIGHT_SHADOWS_SCREEN
                    shadowCoord = i.positionSS;
                #else
                    shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                #endif
                Light mainLight = GetMainLight(shadowCoord);

                float fresnel = H_FresnelSchlickWater(viewDir, normal);

                float3 envReflection = CubemapAmbient(reflDir, 0);
                #ifdef SSR
                    bool   ssrHit;
                    half3  ssrReflection = H_RaymarchSS_Reflection(
                        i.positionWS, normal,
                        _SSRSteps, _SSRStepSize, _SSRThickness, _StepPropagation,
                        _CameraOpaqueTexture, sampler_CameraOpaqueTexture,
                        _CameraDepthTexture,  sampler_CameraDepthTexture,
                        ssrHit);
                    float3 reflection = lerp(envReflection, ssrReflection, ssrHit ? 1.0 : 0.0);
                #else
                    float3 reflection = envReflection;
                #endif
                
                float waveDisplacement = i.positionWS.y - i.initialWS.y;
                half3 sss = WaterSSS(viewDir, normal, mainLight, jacobian, waveDisplacement);  
                //return half4(sss,1);

                float2 refrUV    = i.positionSS.xy / max(i.positionSS.w, 1e-6)
                                     + normal.xz * 0.07;
                float  refrDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture,
                                                             sampler_CameraDepthTexture,
                                                             refrUV);
                #if UNITY_REVERSED_Z
                    bool isSky = refrDepth < 0.0001;
                #else
                    bool isSky = refrDepth > 0.9999;
                #endif
                
                half3 underWS = ComputeWorldSpacePosition(refrUV, refrDepth, UNITY_MATRIX_I_VP);
                half3 refraction = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, refrUV).rgb;
                refraction = lerp(refraction, CubemapAmbient(refrDir, 0), isSky);

                half3 sigmaT      = (1 - _WaterAbsorption.rgb) +  (1 - _WaterScatter.rgb);
                half3 depthTint   = exp(-sigmaT * length(underWS - i.positionWS) / _Transparency);
                refraction = refraction * (isSky ? 0 : depthTint);

                half foamMask   = SAMPLE_DEPTH_TEXTURE(_FoamTexture, sampler_FoamTexture,
                                    i.initialWS.xz * _FoamTexture_ST.xy
                                  + _FoamTexture_ST.zw);
                
                half foamAmount = saturate((foamMask - (1 - jacobian) + _FoamAmount) * _FoamStrength);
                                
                half3 specular = H_PBRSpecular(normal, -viewDir, mainLight.direction,
                                                sss, _Metallic, _Roughness)
                               * mainLight.color
                               * mainLight.shadowAttenuation
                               * (1 - foamAmount);

                float3 transmitted = refraction * (1.0 - fresnel);
                float3 waterColor  = reflection * fresnel + transmitted;

                float  NdotL      = saturate(dot(normal, mainLight.direction));
                float3 foamDiffuse = (foamMask * mainLight.color + SampleSH(normal))
                                   * max(0.75, mainLight.shadowAttenuation) * (NdotL * .5 + .5);
                float3 finalColor  = lerp(waterColor, foamDiffuse, foamAmount);

                finalColor += specular * (1.0 - foamAmount) + sss;
                
                //finalColor = MixFog(finalColor, i.fog);
                if (_FogBlend)
                    return half4(lerp(finalColor, CubemapAmbient(viewDir, 0), saturate(i.fog)), 1);
                else
                    return half4(finalColor, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            Cull Front
            ColorMask 0

            HLSLPROGRAM
            #pragma target 5.0
            #pragma vertex   shadowVert
            #pragma fragment shadowFrag

            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "Gerstner.cginc"

            CBUFFER_START(UnityPerMaterial)
                int _MaxWaves;
            CBUFFER_END

            float3 _LightDirection;
            float3 _LightPosition;

            struct ShadowAttributes { float4 vertex : POSITION; float3 normal : NORMAL; };
            struct ShadowVaryings   { float4 positionCS : SV_POSITION; };

            ShadowVaryings shadowVert(ShadowAttributes IN)
            {
                ShadowVaryings OUT;

                float3 worldPos = mul(unity_ObjectToWorld, float4(IN.vertex.xyz, 1)).xyz;
                float3 normalWS, tangentWS;

                float3 offset = Gerstner_GetOffset(worldPos.xz, _Time.y, _MaxWaves, normalWS, tangentWS);
                worldPos += offset;

                #ifdef _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDir = normalize(worldPos - _LightPosition);
                #else
                    float3 lightDir = _LightDirection;
                #endif

                float4 posCS = TransformWorldToHClip(
                                   ApplyShadowBias(worldPos, normalWS, lightDir));

                #if UNITY_REVERSED_Z
                    posCS.z = min(posCS.z, posCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    posCS.z = max(posCS.z, posCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif

                OUT.positionCS = posCS;
                return OUT;
            }

            half4 shadowFrag(ShadowVaryings IN) : SV_Target { return 0; }

            ENDHLSL
        }
    }

    CustomEditor "GerstnerOceanInspector"
    FallBack Off
}