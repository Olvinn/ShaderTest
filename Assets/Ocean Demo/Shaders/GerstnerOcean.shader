Shader "Custom/GerstnerOcean"
{
    Properties
    {
        _Color ("Color", Color) = (0, 0.5, 1, 1)
        _SSSColor ("SSS Color", Color) = (0, 0.5, 1, 1)
        
        _WaveStrength ("Wave Amplitude", Float) = 0.2
        _WaveLength ("Wave Length", Float) = 2
        _WaveSteepness ("Wave Steepness", Float) = .8
        _SteepnessSuppression ("Steepness Suppression", Range(0, 1)) = .95
        _MaxWaves ("Max Waves", Range(1, 64)) = 64
        _WaveStrengthDistribution ("Wave Strength Distribution", Range(1, 2)) = 1.2
        _WaveLengthDistribution ("Wave Length Distribution", Range(1, 2)) = 1.2
        
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
        //ZWrite On
        
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

            float4 _Color, _SSSColor;
            half _WaveStrength, _WaveLength, _WaveSteepness, _FoamStrength, _FoamAmount, _Transparency;
            half _Metallic, _Roughness, _WaveStrengthDistribution, _WaveLengthDistribution, _SteepnessSuppression;
            int _MaxWaves;
            sampler2D _FoamTexture;
            half4 _FoamTexture_ST;
            
            sampler2D _LocalWaterDetails;
            float4 _MapCenterWS;  
            float4 _MapSizeWS;
            
            #ifdef SSR
            half _SSRThickness, _SSRStepSize, _StepPropagation;
            int _SSRSteps;
            #endif

            #define MAX_WAVES 64
            #define SSR_MAX_STEPS 64
            uniform float2 _WaveDirs[MAX_WAVES];

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
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                
                float3 worldPos = mul(unity_ObjectToWorld, float4(IN.vertex)).xyz;
                
                float3 offset = GerstnerDisplace(
                    worldPos,
                    9.81,
                    _MaxWaves,
                    _WaveDirs,
                    _WaveLength,
                    _WaveLengthDistribution,
                    _WaveStrength,
                    _WaveStrengthDistribution,
                    _WaveSteepness,
                    _SteepnessSuppression
                );
                
                worldPos += offset;
                
                OUT.lodFade = unity_LODFade.y;
                float4 clipPos = TransformWorldToHClip(worldPos);
                OUT.positionCS = clipPos;
                OUT.positionSS = ComputeScreenPos(clipPos);
                OUT.positionWS = worldPos;
                OUT.fog = ComputeFogFactor(OUT.positionCS.z);
                OUT.shadow = TransformWorldToShadowCoord(OUT.positionWS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _FoamTexture);
                
                return OUT;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float2 localUV = (i.positionWS.xz - _MapCenterWS.xz) / _MapSizeWS.xz;
                localUV += 0.5; 
                float4 local = tex2D(_LocalWaterDetails, localUV);

                float3 nLocal = normalize(float3(-local.r, 1.0, -local.g));
                
                WaveDetails wd = GerstnerNormalsAndCurvature(
                    i.positionWS,
                    9.81,
                    _MaxWaves,
                    _WaveDirs,
                    _WaveLength,
                    _WaveLengthDistribution,
                    _WaveStrength,
                    _WaveStrengthDistribution,
                    _WaveSteepness,
                    _SteepnessSuppression);

                wd.normal = TransformObjectToWorldNormal(wd.normal);
                
                float3 viewDir = normalize(i.positionWS - _WorldSpaceCameraPos);
                wd.normal = normalize(lerp(wd.normal, nLocal, 0.35));
                

                Light mainLight = GetMainLight();

                half ndotl = saturate(dot(wd.normal, mainLight.direction));
                half backSSS = saturate(dot(wd.normal, -mainLight.direction)) * 0.4; 
                half wrap = ndotl * 0.5 + 0.5; 
                half transmission = pow(1.0 - saturate(dot(wd.normal, viewDir)), 3.0);
                
                float3 reflection = reflect(viewDir, wd.normal);
                float3 skyColor = CubemapAmbient(viewDir, reflection, 0);

                half light = pow(saturate(dot(mainLight.direction, float3(0,1,0))), .5);
                float3 sss = (backSSS * transmission * wrap) * _SSSColor * mainLight.color * light;
                
                half NdotV = saturate(dot(wd.normal, -viewDir));
                float3 F0 = lerp(float3(0.02, 0.02, 0.02), _Color, _Metallic);
                float3 fresnel = FresnelSchlick(NdotV, F0);
                float3 specular = PBRSpecular(wd.normal, -viewDir, mainLight.direction, _Color, _Metallic, _Roughness) * 
                    mainLight.color * mainLight.shadowAttenuation;

                half d = dot(mainLight.direction, wd.normal) * 0.5 + 0.5;
                
                half foamAmount = saturate(wd.laplacian - _FoamAmount) * _FoamStrength;
                float3 foamColor = float3(1,1,1) * d * light;
                foamAmount *= saturate(tex2D(_FoamTexture, i.uv).r + tex2D(_FoamTexture, i.uv * .1).r);
                specular *= 1 - foamAmount;
                
                float3 color = saturate(d * _Color * light * mainLight.color);
                half fresnelFactor = dot(fresnel, float3(0.333,0.333,0.333));

                #ifdef SSR
                bool ssrHit = false;
                float3 ssrColor = RaymarchSSR_ViewSpace(
                    i.positionWS,
                    wd.normal,
                    _SSRSteps,
                    _SSRStepSize,
                    _SSRThickness,
                    _StepPropagation,
                    ssrHit
                );

                half blend = ssrHit ? 1.0 : 0.0;
                skyColor = lerp(skyColor, ssrColor, blend);
                #endif
                
                color = lerp(lerp(sss + color, skyColor, fresnelFactor), foamColor, saturate(foamAmount));

                half transparency = dot(specular, float3(0.333,0.333,0.333));
                transparency = lerp(saturate(max(transparency, fresnelFactor) * _Transparency), 1, saturate(foamAmount));
                #ifdef LOD_FADE_CROSSFADE
                    transparency *= (sqrt(1-i.lodFade)); 
                #endif
                
                half3 finalColor = saturate(specular + color);
                finalColor.rgb = MixFog(finalColor.rgb, i.fog);
                
                return half4(finalColor, transparency);
            }
            ENDHLSL
        }
    }

    CustomEditor "GerstnerOceanInspector"
    
    FallBack Off
}