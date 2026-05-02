Shader "Custom/GerstnerOcean"
{
    Properties
    {
        _Noise ("Noise", 2D) = "white" {}
        
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
            float4 _MapCenterWS;  
            float4 _MapSizeWS;
            CBUFFER_END

            TEXTURE2D_X(_FoamTexture);              SAMPLER(sampler_FoamTexture);
            TEXTURE2D_X(_LocalWaterDetails);        SAMPLER(sampler_LocalWaterDetails);
            TEXTURE2D_X(_CameraOpaqueTexture);      SAMPLER(sampler_CameraOpaqueTexture);
            TEXTURE2D_X_FLOAT(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);
            TEXTURE2D_X_FLOAT(_Noise);              SAMPLER(sampler_Noise);
            
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
            
            float3 GO_ReadDetailsNormal(float2 uv)
            {
                uv += 0.5; 
                float4 local = SAMPLE_TEXTURE2D(_LocalWaterDetails, sampler_LocalWaterDetails, uv);
                return normalize(float3(-local.r, 1.0, -local.g));
            }
            
            float GO_HenyeyGreenstein(float cosTheta, float g)
            {
                float g2 = g * g;
                float denom = 1.0 + g2 - 2.0 * g * cosTheta;
                return (1.0 - g2) / (4.0 * PI * pow(denom, 1.5));
            }
            
            half3 GO_GetScattering(float3 normal, Light mainLight, float3 viewDir, float depth)
            {
                float cosTheta = dot(mainLight.direction, viewDir);
                float phase = GO_HenyeyGreenstein(cosTheta, .5);
                float3 sigmaA = _SSSColor; // color loss
                float3 sigmaS = float3(0.02, 0.05, 0.08); // scattered light
                float3 sigmaT = sigmaA + sigmaS;
                
                float NdotL = abs(dot(normal, mainLight.direction));
                float NdotV = abs(dot(normal, viewDir));

                float rawDepth = saturate(depth * 2);
                float lightPath = rawDepth / max(NdotL, 0.1);
                float viewPath  = rawDepth / max(NdotV, 0.1);

                float opticalDepth = min(lightPath + viewPath, 8);

                depth = opticalDepth;
                float3 T = exp(-sigmaT * depth);
                float3 singleScatter = mainLight.color.rgb * sigmaS * phase * (1.0 - T) / max(sigmaT, 0.0001);

                return singleScatter * .8;
            }

            half4 frag(Varyings i) : SV_Target
            {                
                float3 normal = GO_ReadDetailsNormal((i.positionWS.xz - _MapCenterWS.xz) / _MapSizeWS.xz);
                float jacobianCoeff = 0;
                
                half noise = smoothstep(0,1,SAMPLE_TEXTURE2D(_Noise, sampler_Noise, (i.positionWS.xz + _Time.y * 5) * .001));
               // return half4(noise, noise, noise, 1);
                
                G_GetNormalLaplacian(i.initialWS.xz, _Time.y, _MaxWaves, _WaveDirs, normal, jacobianCoeff, noise);
                
                float3 viewDir = normalize(i.positionWS - _WorldSpaceCameraPos); 
                
                float4 shadowCoord;
                #ifdef _MAIN_LIGHT_SHADOWS_SCREEN
                    shadowCoord = ComputeScreenPos(i.positionCS);
                #else
                    shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                #endif

                Light mainLight = GetMainLight(shadowCoord);

                half fakeThickness = saturate((i.positionWS.y * .01 +  jacobianCoeff));
                half3 sss = GO_GetScattering(normal, mainLight, viewDir, fakeThickness);
                
                float fresnel = H_FresnelSchlickWater(viewDir, normal);
                
                float4 cubemapReflection = 1;
                float3 redlectionDir = reflect(viewDir, normal);
                float3 refractionDir = refract(viewDir, -normal, 1.01);
                cubemapReflection.rgb = CubemapAmbient(redlectionDir, 0);
                
                half d = saturate(dot(mainLight.direction, normal));
                half3 color = 0;
                
                half3 specular = H_PBRSpecular(normal, -viewDir, mainLight.direction, _Color, _Metallic, _Roughness) * 
                    mainLight.color * mainLight.shadowAttenuation;
                
                half foamAmount = saturate(jacobianCoeff - _FoamAmount) * _FoamStrength;
                half3 foamColor = half3(1,1,1);
                half foamMask = SAMPLE_DEPTH_TEXTURE(_FoamTexture, sampler_FoamTexture, i.positionWS.xz * _FoamTexture_ST.xy + _FoamTexture_ST.zw);
                foamAmount = foamAmount * foamMask;
                
                #ifdef SSR
                bool ssrHit = false;
                half3 ssrReflection = H_RaymarchSSR_ViewSpace(
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
                cubemapReflection.rgb = lerp(cubemapReflection, ssrReflection, blend);
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
                    underColor = saturate(GetDepthTint(i.positionWS, underWS, underColor, 1 - _SSSColor, _Color, _Transparency));
                
                color = lerp(underColor,  color, fresnel) * (1 - foamAmount);
                color = lerp(color.rgb, foamColor, foamAmount);
                color = color * d * mainLight.color * max(.5, mainLight.shadowAttenuation);
                specular *= 1 - foamAmount;
                color += cubemapReflection * fresnel * (1 - foamAmount);
                color += sss;
                
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