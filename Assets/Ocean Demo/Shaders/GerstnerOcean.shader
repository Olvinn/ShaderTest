Shader "Custom/GerstnerOcean"
{
    Properties
    {
        _Color ("Color", Color) = (0, 0.5, 1, 1)
        _SSSColor ("SSS Color", Color) = (0, 0.5, 1, 1)
        _Transparency ("Transparency", Range(0, 1000)) = 0
        
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
            #pragma shader_feature SSR
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "Helper.cginc"
            #include "Gerstner.cginc"

            CBUFFER_START(UnityPerMaterial)
            float4 _Color, _SSSColor, _FoamTexture_ST;
            half FoamStrength, _FoamAmount, _FoamStrength, _Transparency;
            half _Metallic, _Roughness;
            int _MaxWaves;
            CBUFFER_END

            TEXTURE2D_X(_FoamTexture);              SAMPLER(sampler_FoamTexture);
            TEXTURE2D_X(_LocalWaterDetails);        SAMPLER(sampler_LocalWaterDetails);
            TEXTURE2D_X(_CameraOpaqueTexture);      SAMPLER(sampler_CameraOpaqueTexture);
            TEXTURE2D_X_FLOAT(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);
            
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
                DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 2);
                float4 positionSS   : TEXCOORD4;
                half2 uv            : TEXCOORD5;
                float4 shadow       : TEXCOORD6;
                float3 initialWS    : TEXCOORD7;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                
                float3 worldPos = mul(unity_ObjectToWorld, float4(IN.vertex)).xyz;
                OUT.initialWS = worldPos;
                
                float3 offset = GetGerstnerOffset(worldPos.xz, _Time.y, _WaveDirs, _MaxWaves);
                worldPos += offset;
                
                float4 clipPos = TransformWorldToHClip(worldPos);
                OUT.positionCS = clipPos;
                OUT.positionSS = ComputeScreenPos(clipPos);
                OUT.positionWS = worldPos;
                OUT.fog = ComputeFogFactor(OUT.positionCS.z);
                OUT.shadow = TransformWorldToShadowCoord(worldPos);
                OUT.uv = IN.uv;
                
                return OUT;
            }

            half4 frag(Varyings i) : SV_Target
            {                
                float2 localUV = (i.positionWS.xz - _MapCenterWS.xz) / _MapSizeWS.xz;
                localUV += 0.5; 
                float4 local = SAMPLE_TEXTURE2D(_LocalWaterDetails, sampler_LocalWaterDetails, localUV);

                float3 nLocal = normalize(float3(-local.r, 1.0, -local.g));
                
                float3 normal = nLocal;
                float laplacian = 0;
                
                GetGerstnerNormalLaplacian(i.initialWS.xz, _Time.y, _MaxWaves, _WaveDirs, normal, laplacian);
                
                float3 viewDir = normalize(i.positionWS - _WorldSpaceCameraPos);  
                
                #ifdef _MAIN_LIGHT_SHADOWS_SCREEN
                    float4 shadowCoord = ComputeScreenPos(i.positionCS);
                #else
                    float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                #endif

                Light mainLight = GetMainLight(shadowCoord);

                half ndotl = saturate(dot(normal, mainLight.direction));
                half backSSS = saturate(dot(normal, -mainLight.direction)) * 0.4; 
                half wrap = ndotl * 0.5 + 0.5; 
                half transmission = pow(1.0 - saturate(dot(normal, viewDir)), 3.0);
                
                float fresnel = FresnelSchlickWater(viewDir, normal);
                
                float4 skyColor = 1;
                float3 redlectionDir = reflect(viewDir, normal);
                float3 refractionDir = refract(viewDir, -normal, .75);
                skyColor.rgb = CubemapAmbient(redlectionDir, 0);
                //skyColor.rgb = lerp(skyColor.rgb, CubemapAmbient(-viewDir, normal, 0), 1 - fresnel);

                float3 sss = backSSS * transmission * wrap * _SSSColor * mainLight.color;
                
                half d = dot(mainLight.direction, normal) * 0.5 + 0.5;
                float4 color = 1;
                color.rgb = d * _Color * mainLight.color;
                
                float3 specular = PBRSpecular(normal, -viewDir, mainLight.direction, _Color, _Metallic, _Roughness) * 
                    mainLight.color * mainLight.shadowAttenuation;
                
                half foamAmount = saturate(smoothstep(0,1,laplacian) - _FoamAmount) * _FoamStrength;
                float3 foamColor = d + sss;
                foamAmount = saturate(SAMPLE_DEPTH_TEXTURE(_FoamTexture, sampler_FoamTexture, i.uv * _FoamTexture_ST.xy + _FoamTexture_ST.zw).r * foamAmount);
                specular *= 1 - foamAmount;
                
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
                skyColor.rgb = lerp(skyColor, ssrColor, blend);
                #endif
                  
                
                float2 underUV = i.positionSS / max(i.positionCS.w, 1e-6) + normal.xz * .07;
                
                half depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, underUV);     
                #if UNITY_REVERSED_Z
                    bool isSky = depth < 0.0001;
                #else
                    bool isSky = depth > 0.9999;
                #endif
                float3 underWS = ComputeWorldSpacePosition(underUV, depth, UNITY_MATRIX_I_VP);
                half3 underColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, underUV).rgb;
                underColor = lerp(underColor, CubemapAmbient(refractionDir, 0), isSky);
                if (dot(-viewDir, normal) > 0)
                    underColor = saturate(GetDepthTint(i.positionWS, underWS, underColor, _SSSColor, color, _Transparency));
                
                color.rgb += lerp(underColor, skyColor, fresnel);
                color.rgb += sss;
                //color.rgb = lerp(underColor, color, fresnel);
                //color.rgb = color + skyColor * fresnel;
                color.rgb = lerp(color, foamColor, saturate(foamAmount));
                
                half3 finalColor = color + specular;
                finalColor = MixFog(finalColor, i.fog);
                
                return half4(finalColor, 1);
            }
            ENDHLSL
        }
    }

SubShader
    {
        Name "ShadowCaster"
        Tags { "LightMode" = "ShadowCaster" }

        ZWrite On
        ZTest LEqual
        Cull Front
        ColorMask 0
            
        Pass
        {
            HLSLPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "Helper.cginc"
            #include "Gerstner.cginc"

            CBUFFER_START(UnityPerMaterial)
            int _MaxWaves;
            CBUFFER_END

            #define MAX_WAVES 64
            uniform float4 _WaveDirs[MAX_WAVES];

            struct Attributes
            {
                float4 vertex : POSITION;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float3 initialWS   : TEXCOORD0;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                
                float3 worldPos = mul(unity_ObjectToWorld, float4(IN.vertex)).xyz;
                OUT.initialWS = worldPos;
                
                float3 offset = GetGerstnerOffset(worldPos.xz, _Time.y, _WaveDirs, _MaxWaves);
                worldPos += offset;
                
                float4 clipPos = TransformWorldToHClip(worldPos);
                OUT.positionCS = clipPos;
                
                return OUT;
            }

            half4 frag(Varyings i) : SV_Target
            {                
                return 0;
            }
            ENDHLSL
        }
    }

    CustomEditor "GerstnerOceanInspector"
    
    FallBack Off
}