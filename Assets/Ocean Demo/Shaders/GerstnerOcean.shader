Shader "Custom/GerstnerOcean"
{
    Properties
    {
        _Color ("Color", Color) = (0, 0.5, 1, 1)
        _SSSColor ("SSS Color", Color) = (0, 0.5, 1, 1)
        _Transparency ("Transparency", Range(0, 1)) = 0
        
        _MaxWaves ("Max Waves", Range(1, 64)) = 64
        
        _FoamTexture ("Foam Texture", 2D) = "white" {}
        _FoamAmount ("Foam Amount", Float) = 1
        _FoamStrength ("Foam Strength", Float) = 1
        
        _Metallic ("Metallic", Range(0,1)) = .5
        _Roughness ("Roughness", Range(0,1)) = .5
        
        _SSRSteps ("SSR Steps", Integer) = 32
        _SSRStepSize ("SSR Step Size", Range(0.01, 5)) = .5
        _StepPropagation ("SSR Step Propagation", Range(0, 1)) = .01
        _SSRThickness ("SSR Thickness", Range(0.01, 1)) = .5
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" "RenderQueue" = "Transparent" }
        Cull Off
        
        Pass
        {
            HLSLPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight
            #pragma shader_feature SSR

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "Helper.cginc"
            #include "Gerstner.cginc"

            CBUFFER_START(UnityPerMaterial)
            float4 _Color, _SSSColor;
            half FoamStrength, _FoamAmount, _FoamStrength, _Transparency;
            half _Metallic, _Roughness;
            int _MaxWaves;
            CBUFFER_END

            TEXTURE2D_X(_FoamTexture);              SAMPLER(sampler_FoamTexture);
            TEXTURE2D_X(_CameraOpaqueTexture);      SAMPLER(sampler_CameraOpaqueTexture);
            TEXTURE2D_X_FLOAT(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);
            
            sampler2D _LocalWaterDetails;
            float4 _MapCenterWS;  
            float4 _MapSizeWS;
            
            #ifdef SSR
            half _SSRThickness, _SSRStepSize, _StepPropagation;
            int _SSRSteps;
            #endif

            #define MAX_WAVES 64
            #define SSR_MAX_STEPS 64
            uniform float4 _WaveDirs[MAX_WAVES];

            struct Attributes
            {
                float4 vertex : POSITION;
                half2 uv      : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float3 positionWS   : TEXCOORD0;
                float3 fog          : TEXCOORD1;
                half lodFade        : TEXCOORD2;
                float4 positionSS   : TEXCOORD4;
                half2 uv            : TEXCOORD5;
                float3 shadow       : TEXCOORD6;
                float3 initialWS   : TEXCOORD7;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                
                float3 worldPos = mul(unity_ObjectToWorld, float4(IN.vertex)).xyz;
                OUT.initialWS = worldPos;
                
                float3 offset = GetGerstnerOffset(worldPos.xz, _Time.y, _WaveDirs, _MaxWaves);
                
                worldPos += offset;
                
                OUT.lodFade = unity_LODFade.y;
                float4 clipPos = TransformWorldToHClip(worldPos);
                OUT.positionCS = clipPos;
                OUT.positionSS = ComputeScreenPos(clipPos);
                OUT.positionWS = worldPos;
                OUT.fog = ComputeFogFactor(OUT.positionCS.z);
                OUT.shadow = TransformWorldToShadowCoord(OUT.positionWS);
                OUT.uv = IN.uv;
                
                return OUT;
            }

            half4 frag(Varyings i) : SV_Target
            {                
                float3 normal = 0;
                float laplacian = 0;
                
                GetGerstnerNormalLaplacian(i.initialWS.xz, _Time.y, _MaxWaves, _WaveDirs, normal, laplacian);
                
                float3 viewDir = normalize(i.positionWS - _WorldSpaceCameraPos);                

                Light mainLight = GetMainLight();

                half ndotl = saturate(dot(normal, mainLight.direction));
                half backSSS = saturate(dot(normal, -mainLight.direction)) * 0.4; 
                half wrap = ndotl * 0.5 + 0.5; 
                half transmission = pow(1.0 - saturate(dot(normal, viewDir)), 3.0);
                
                float3 reflection = reflect(viewDir, normal);
                float3 skyColor = CubemapAmbient(viewDir, normal, 0);

                half light = dot(mainLight.direction, normal) *.5 + .5;
                float3 sss = (backSSS * transmission * wrap) * _SSSColor * mainLight.color * light;
                
                half NdotV = saturate(dot(normal, -viewDir));
                float3 F0 = lerp(float3(0.02, 0.02, 0.02), _Color, _Metallic);
                float3 fresnel = FresnelSchlick(NdotV, F0);
                float3 specular = PBRSpecular(normal, -viewDir, mainLight.direction, _Color, _Metallic, _Roughness) * 
                    mainLight.color * mainLight.shadowAttenuation;

                half d = dot(mainLight.direction, normal) * 0.5 + 0.5;
                
                half foamAmount = saturate(smoothstep(0,1,laplacian) - _FoamAmount) * _FoamStrength;
                float3 foamColor = d * light;
                foamAmount = saturate(SAMPLE_DEPTH_TEXTURE(_FoamTexture, sampler_FoamTexture, i.uv).r * foamAmount);
                specular *= 1 - foamAmount;
                
                float3 color = d * _Color * light * mainLight.color;
                half fresnelFactor = fresnel;

                #ifdef SSR
                bool ssrHit = false;
                float3 ssrColor = RaymarchSSR_ViewSpace(
                    i.positionWS,
                    normal,
                    _SSRSteps,
                    _SSRStepSize,
                    _SSRThickness,
                    _StepPropagation,
                    _CameraOpaqueTexture,
                    sampler_CameraOpaqueTexture,
                    _CameraDepthTexture,
                    sampler_CameraDepthTexture,
                    ssrHit
                );

                half blend = ssrHit ? 1.0 : 0.0;
                skyColor = lerp(skyColor, ssrColor, blend);
                #endif
                  
                float2 underUV = i.positionSS / max(i.positionCS.w, 1e-6) + normal.xz * .05;
                
                half depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, underUV);         
                float3 underWS = ComputeWorldSpacePosition(underUV, depth, UNITY_MATRIX_I_VP);
                half depthWS = length(i.positionWS - underWS) / 20;
                half3 underColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, underUV).rgb;
                color = lerp(lerp(sss + color, skyColor, fresnelFactor), foamColor, saturate(foamAmount));
                underColor = lerp(underColor,  color, saturate(depthWS) * fresnelFactor);

                half transparency = saturate(1-fresnelFactor) * _Transparency;
                
                half3 finalColor = specular + color;
                finalColor.rgb = MixFog(finalColor.rgb, i.fog);
                finalColor.rgb = finalColor + underColor * transparency;
                
                return half4(finalColor, 1);
            }
            ENDHLSL
        }
    }

//SubShader
//    {
//        Name "ShadowCaster"
//        Tags { "LightMode" = "ShadowCaster" }
//        
//        Pass
//        {
//            HLSLPROGRAM
//            #pragma target 5.0
//            #pragma vertex vert
//            #pragma fragment frag
//
//            #pragma multi_compile _ LOD_FADE_CROSSFADE
//            #pragma multi_compile_fog
//            #pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight
//            #pragma shader_feature SSR
//            
//            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
//            #include "Helper.cginc"
//            #include "Gerstner.cginc"
//
//            CBUFFER_START(UnityPerMaterial)
//            float4 _Color, _SSSColor;
//            half _WaveStrength, _WaveLength, _WaveSteepness, _FoamStrength, _FoamAmount, _Transparency;
//            half _Metallic, _Roughness, _WaveStrengthDistribution, _WaveLengthDistribution, _SteepnessSuppression;
//            int _MaxWaves;
//            sampler2D _FoamTexture;
//            half4 _FoamTexture_ST;
//            CBUFFER_END
//
//            TEXTURE2D_X(_CameraOpaqueTexture);      SAMPLER(sampler_CameraOpaqueTexture);
//            TEXTURE2D_X_FLOAT(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);
//            
//            sampler2D _LocalWaterDetails;
//            float4 _MapCenterWS;  
//            float4 _MapSizeWS;
//            
//            #ifdef SSR
//            half _SSRThickness, _SSRStepSize, _StepPropagation;
//            int _SSRSteps;
//            #endif
//
//            #define MAX_WAVES 64
//            #define SSR_MAX_STEPS 64
//            uniform float2 _WaveDirs[MAX_WAVES];
//
//            struct Attributes
//            {
//                float4 vertex : POSITION;
//                half2 uv      : TEXCOORD0;
//            };
//
//            struct Varyings
//            {
//                float4 positionCS   : SV_POSITION;
//                float3 positionWS   : TEXCOORD0;
//                float3 fog          : TEXCOORD1;
//                half lodFade        : TEXCOORD2;
//                float4 positionSS   : TEXCOORD4;
//                half2 uv            : TEXCOORD5;
//                float3 shadow       : TEXCOORD6;
//                float3 initialWS   : TEXCOORD7;
//            };
//
//            Varyings vert(Attributes IN)
//            {
//                Varyings OUT = (Varyings)0;
//                
//                float3 worldPos = mul(unity_ObjectToWorld, float4(IN.vertex)).xyz;
//                OUT.initialWS = worldPos;
//                
//                float3 offset = GetGerstnerOffset(worldPos.xz, _Time.y, _WaveDirs, _MaxWaves, _WaveLength,_WaveStrength,  _WaveSteepness);
//                
//                worldPos += offset;
//                
//                OUT.lodFade = unity_LODFade.y;
//                float4 clipPos = TransformWorldToHClip(worldPos);
//                OUT.positionCS = clipPos;
//                OUT.positionSS = ComputeScreenPos(clipPos);
//                OUT.positionWS = worldPos;
//                OUT.fog = ComputeFogFactor(OUT.positionCS.z);
//                OUT.shadow = TransformWorldToShadowCoord(OUT.positionWS);
//                OUT.uv = TRANSFORM_TEX(IN.uv, _FoamTexture);
//                
//                return OUT;
//            }
//
//            half4 frag(Varyings i) : SV_Target
//            {
//                float2 localUV = (i.positionWS.xz - _MapCenterWS.xz) / _MapSizeWS.xz;
//                localUV += 0.5; 
//                
//                float3 normal = 0;
//                float laplacian = 0;
//                
//                GetGerstnerNormalLaplacian(i.initialWS.xz, _Time.y, _MaxWaves, _WaveDirs, _WaveLength, _WaveStrength, _WaveSteepness, normal, laplacian);
//
//                //normal = TransformObjectToWorldNormal(normal);
//                
//                float3 viewDir = normalize(i.positionWS - _WorldSpaceCameraPos);                
//
//                Light mainLight = GetMainLight();
//
//                half ndotl = saturate(dot(normal, mainLight.direction));
//                half backSSS = saturate(dot(normal, -mainLight.direction)) * 0.4; 
//                half wrap = ndotl * 0.5 + 0.5; 
//                half transmission = pow(1.0 - saturate(dot(normal, viewDir)), 3.0);
//                
//                float3 reflection = reflect(viewDir, normal);
//                float3 skyColor = CubemapAmbient(viewDir, reflection, 0);
//
//                half light = pow(saturate(dot(mainLight.direction, float3(0,1,0))), .5);
//                float3 sss = (backSSS * transmission * wrap) * _SSSColor * mainLight.color * light;
//                
//                half NdotV = saturate(dot(normal, -viewDir));
//                float3 F0 = lerp(float3(0.02, 0.02, 0.02), _Color, _Metallic);
//                float3 fresnel = FresnelSchlick(NdotV, F0);
//                float3 specular = PBRSpecular(normal, -viewDir, mainLight.direction, _Color, _Metallic, _Roughness) * 
//                    mainLight.color * mainLight.shadowAttenuation;
//
//                half d = dot(mainLight.direction, normal) * 0.5 + 0.5;
//                
//                half foamAmount = saturate(laplacian - _FoamAmount) * _FoamStrength;
//                float3 foamColor = d * light;
//                foamAmount *= saturate(tex2D(_FoamTexture, i.uv).r);
//                specular *= 1 - foamAmount;
//                
//                float3 color = d * _Color * light * mainLight.color;
//                half fresnelFactor = dot(fresnel, float3(0.333,0.333,0.333));
//
//                #ifdef SSR
//                bool ssrHit = false;
//                float3 ssrColor = RaymarchSSR_ViewSpace(
//                    i.positionWS,
//                    normal,
//                    _SSRSteps,
//                    _SSRStepSize,
//                    _SSRThickness,
//                    _StepPropagation,
//                    _CameraOpaqueTexture,
//                    sampler_CameraOpaqueTexture,
//                    _CameraDepthTexture,
//                    sampler_CameraDepthTexture,
//                    ssrHit
//                );
//
//                half blend = ssrHit ? 1.0 : 0.0;
//                skyColor = lerp(skyColor, ssrColor, blend);
//                #endif
//                  
//                float2 underUV = i.positionSS / max(i.positionCS.w, 1e-6) + normal.xz * .05;
//                
//                half depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, underUV);         
//                float3 underWS = ComputeWorldSpacePosition(underUV, depth, UNITY_MATRIX_I_VP);
//                half depthWS = length(i.positionWS - underWS) / 20;
//                half3 underColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, underUV).rgb;
//                color = lerp(lerp(sss + color, skyColor, fresnelFactor), foamColor, saturate(foamAmount));
//                underColor = lerp(underColor,  color, saturate(depthWS));
//
//                half transparency = saturate(1-fresnelFactor) * _Transparency;
//                
//                half3 finalColor = specular + color;
//                finalColor.rgb = MixFog(finalColor.rgb, i.fog);
//                finalColor.rgb = finalColor + underColor * transparency;
//                //finalColor.rgb = half3(mainLight.shadowAttenuation,mainLight.shadowAttenuation,mainLight.shadowAttenuation);
//                
//                return half4(finalColor, 1);
//            }
//            ENDHLSL
//        }
//    }

    CustomEditor "GerstnerOceanInspector"
    
    FallBack Off
}