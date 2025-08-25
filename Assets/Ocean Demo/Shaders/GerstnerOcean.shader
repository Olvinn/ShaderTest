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
        _SSRThickness ("SSR Thickness", Range(0.01, 1)) = .5
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderQueue" = "Opaque" "LightMode" = "ForwardBase" }
        //ZWrite On
        
        Pass
        {
            CGPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight
            #pragma shader_feature SSR

            #include "UnityCG.cginc"
            #include "Helper.cginc"
            #include "UnityLightingCommon.cginc"
            #include "AutoLight.cginc"
            #include "Gerstner.cginc"

            float4 _Color, _SSSColor;
            half _WaveStrength, _WaveLength, _WaveSteepness, _FoamStrength, _FoamAmount, _Transparency;
            half _Metallic, _Roughness, _WaveStrengthDistribution, _WaveLengthDistribution, _SteepnessSuppression;
            int _MaxWaves;
            sampler2D _LastFrameColor, _FoamTexture;
            sampler2D _CameraDepthTexture;
            half4 _FoamTexture_ST;
            
            sampler2D _LocalWaterDetails;
            float4 _MapCenterWS;  
            float4 _MapSizeWS;
            
            #ifdef SSR
            half _SSRThickness, _SSRStepSize;
            int _SSRSteps;
            #endif

            #define MAX_WAVES 64
            #define SSR_MAX_STEPS 64
            uniform float2 _WaveDirs[MAX_WAVES];

            struct appdata
            {
                float4 vertex : POSITION;
                half2 uv : TEXCOORD0;
            };

            struct v2t
            {
                float4 pos : SV_POSITION;
                float3 positionWS   : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                half lodFade : TEXCOORD2;
                SHADOW_COORDS(3)
                float4 screenPos : TEXCOORD4;
                half2 uv : TEXCOORD5;
            };

            v2t vert(appdata v)
            {
                v2t o;
                
                float3 worldPos = mul(unity_ObjectToWorld, float4(v.vertex)).xyz;
                
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
                
                UNITY_INITIALIZE_OUTPUT(v2t, o);
                o.lodFade = unity_LODFade.y;
                float4 clipPos = UnityWorldToClipPos(worldPos);
                o.pos = clipPos;
                o.screenPos = ComputeScreenPos(clipPos);
                o.positionWS = worldPos;
                UNITY_TRANSFER_FOG(o,o.pos);
                TRANSFER_SHADOW_WPOS(o, worldPos);
                o.uv = TRANSFORM_TEX(v.uv, _FoamTexture);
                
                return o;
            }

            fixed4 frag(v2t i) : SV_Target
            {
                float2 localUV = (i.positionWS.xz - _MapCenterWS.xz) / _MapSizeWS.xz;
                localUV += 0.5;
                float4 local = tex2D(_LocalWaterDetails, localUV);

                // Add local slope into normal reconstruction (cheap hack):
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
                
                float3 viewDir = normalize(i.positionWS - _WorldSpaceCameraPos);
                wd.normal = normalize(lerp(wd.normal, nLocal, 0.35)); // blend factor to taste
                //return float4(local);
                
                half shadow = SHADOW_ATTENUATION(i);

                float3 lightDir = _WorldSpaceLightPos0.xyz;

                half ndotl = saturate(dot(wd.normal, lightDir));
                half backSSS = saturate(dot(wd.normal, -lightDir)) * 0.4; 
                half wrap = ndotl * 0.5 + 0.5; 
                half transmission = pow(1.0 - saturate(dot(wd.normal, viewDir)), 3.0);
                
                float3 reflection = reflect(viewDir, wd.normal);
                float3 skyColor = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflection, 0);

                half light = pow(saturate(dot(lightDir, float3(0,1,0))), .5);
                float3 sss = (backSSS * transmission * wrap) * _SSSColor * _LightColor0 * light;
                
                half NdotV = saturate(dot(wd.normal, -viewDir));
                float3 F0 = lerp(float3(0.02, 0.02, 0.02), _Color, _Metallic);
                float3 fresnel = FresnelSchlick(NdotV, F0);
                float3 specular = PBRSpecular(wd.normal, -viewDir, lightDir, _Color, _Metallic, _Roughness) * _LightColor0 * shadow;

                half d = dot(lightDir, wd.normal) * 0.5 + 0.5;
                
                half foamAmount = saturate(wd.laplacian - _FoamAmount) * _FoamStrength;
                float3 foamColor = float3(1,1,1) * d * light;
                foamAmount *= saturate(tex2D(_FoamTexture, i.uv).r + tex2D(_FoamTexture, i.uv * .1).r);
                specular *= 1 - foamAmount;
                
                float3 color = saturate(d * _Color * light * _LightColor0);
                color *= lerp(1, .25, shadow);
                half fresnelFactor = dot(fresnel, float3(0.333,0.333,0.333));

                #ifdef SSR
                bool ssrHit = false;
                float3 ssrColor = RaymarchSSR_ViewSpace(
                    i.positionWS,
                    reflection,
                    _SSRSteps,
                    _SSRStepSize,
                    _SSRThickness,
                    _CameraDepthTexture,
                    _LastFrameColor,
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
                
                float3 finalColor = saturate(specular + color);
                UNITY_APPLY_FOG(i.fogCoord, finalColor);
                
                return float4(finalColor, transparency);
            }
            ENDCG
        }

        Pass //shadow casting
        {
            Tags{ "LightMode" = "ShadowCaster"  }
            CGPROGRAM
            
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "Gerstner.cginc"

            float _WaveStrength, _WaveLength, _WaveSteepness, _FoamStrength, _FoamAmount, _Transparency;
            float _WaveStrengthDistribution, _WaveLengthDistribution, _MaxWaves, _SteepnessSuppression;

            #define MAX_WAVES 64
            #define UNITY_PASS_SHADOWCASTER
            uniform float2 _WaveDirs[MAX_WAVES];

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2t
            {
                float3 objectPos : INTERNALTESSPOS;
                float4 pos : SV_POSITION;
            };

            v2t vert(appdata v)
            {
                v2t o;
                
                float3 worldPos = mul(unity_ObjectToWorld, float4(v.vertex)).xyz;
                
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
                
                UNITY_INITIALIZE_OUTPUT(v2t, o);
                o.pos = UnityWorldToClipPos(worldPos);
                
                return o;
            }

            fixed4 frag(v2t i) : SV_Target
            {
                SHADOW_CASTER_FRAGMENT(i)
            }
            ENDCG
        }
    }

    CustomEditor "GerstnerOceanInspector"
    
    FallBack Off
}