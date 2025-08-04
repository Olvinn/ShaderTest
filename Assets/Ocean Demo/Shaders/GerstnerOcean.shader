Shader "Custom/GerstnerOcean"
{
    Properties
    {
        _Color ("Color", Color) = (0, 0.5, 1, 1)
        _SSSColor ("SSS Color", Color) = (0, 0.5, 1, 1)
        _WaveStrength ("Wave Amplitude", Float) = 0.2
        _WaveLength ("Wave Length", Float) = 2
        _WaveSteepness ("Wave Steepness", Float) = .8
        _MaxWaves ("Max Waves", Range(1, 64)) = 64
        _WaveStrengthDistribution ("Wave Strength Distribution", Range(1, 2)) = 1.2
        _WaveLengthDistribution ("Wave Length Distribution", Range(1, 2)) = 1.2
        _FoamAmount ("Foam Amount", Float) = 1
        _FoamStrength ("Foam Strength", Float) = 1
        _TessFactor ("Tessellation Factor", Float) = 3
        _Metallic ("Metallic", Range(0,1)) = .5
        _Roughness ("Roughness", Range(0,1)) = .5
        _Transparency ("Transparency", Float) = 20
        _SSRSteps ("SSR Steps", Integer) = 32
        _SSRStepSize ("SSR Step Size", Range(0.1, 5)) = .5
        _SSRThickness ("SSR Thickness", Range(0.1, 1)) = .5
    }

    SubShader
    {
        //Tags { "RenderType" = "Transparent" "RenderQueue" = "Transparent" "LightMode" = "ForwardBase" }
        Tags { "RenderType" = "Opaque" "RenderQueue" = "Opaque" "LightMode" = "ForwardBase" }
        ZWrite On
        //Blend SrcAlpha OneMinusSrcAlpha
        
        Pass
        {
            CGPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma hull hull
            #pragma domain domain
            #pragma fragment frag

            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight

            #include "UnityCG.cginc"
            #include "Helper.cginc"
            #include "UnityLightingCommon.cginc"
            #include "AutoLight.cginc"

            float4 _Color, _SSSColor;
            float _WaveStrength, _WaveLength, _WaveSteepness, _TessFactor, _FoamStrength, _FoamAmount, _Transparency;
            float _Metallic, _Roughness, _WaveStrengthDistribution, _WaveLengthDistribution, _MaxWaves, _SSRStepSize;
            float _SSRThickness;
            int _SSRSteps;
            sampler2D _LastFrameColor;
            sampler2D _CameraDepthTexture;

            #define MAX_WAVES 64
            #define SSR_MAX_STEPS 32
            uniform float2 _WaveDirs[MAX_WAVES];

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2t
            {
                float3 objectPos : INTERNALTESSPOS;
            };

            struct Interpolators
            {
                float4 pos : SV_POSITION;
                float3 positionWS   : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float lodFade : TEXCOORD2;
                SHADOW_COORDS(3)
                float4 screenPos : TEXCOORD4;
            };

            struct TessellationFactors
            {
                float edge[3] : SV_TessFactor;
                float inside  : SV_InsideTessFactor;
            };

            v2t vert(appdata v)
            {
                v2t o;
                o.objectPos = v.vertex.xyz;
                return o;
            }

            [domain("tri")]
            [outputcontrolpoints(3)]
            [outputtopology("triangle_cw")]
            [patchconstantfunc("PatchConstantFunction")]
            [partitioning("fractional_even")]
            v2t hull(InputPatch<v2t, 3> patch, uint id : SV_OutputControlPointID)
            {
                return patch[id];
            }

            TessellationFactors PatchConstantFunction(InputPatch<v2t, 3> patch)
            {
                TessellationFactors f;
                f.edge[0] = _TessFactor;
                f.edge[1] = _TessFactor;
                f.edge[2] = _TessFactor;
                f.inside  = _TessFactor;

                return f;
            }

            void WaveDistribution(int i, inout float waveLength, inout float waveAmplitude)
            {
                waveLength = _WaveLength / pow(_WaveLengthDistribution, i);
                waveAmplitude = _WaveStrength / pow(_WaveStrengthDistribution, i);
            }

            float3 GerstnerDisplace(
                float3 posOS,
                float baseSpeed
            )
            {
                float3 totalOffset = float3(0, 0, 0);

                int maxWaves = min(MAX_WAVES, _MaxWaves);
                
                for (int i = 0; i < maxWaves; i++)
                {
                    float2 dir = _WaveDirs[i];
                    float wavelength = 0;
                    float amplitude = 0;
                    WaveDistribution(i, wavelength, amplitude);
                    float k = UNITY_PI / wavelength;
                    float speed = sqrt(baseSpeed * k);
                    float phase = k * dot(dir, posOS.xz) - speed * _Time.y;

                    float sinP = sin(phase);
                    float cosP = cos(phase);

                    float Qi = _WaveSteepness / (k * amplitude * MAX_WAVES);

                    totalOffset.x += Qi * dir.x * amplitude * cosP;
                    totalOffset.z += Qi * dir.y * amplitude * cosP;
                    totalOffset.y += amplitude * sinP;
                }
                
                return totalOffset;
            }

            float3 GerstnerNormalsAndCurvature(
                float3 posOS,
                float baseSpeed,
                inout float laplacian
            )
            {
                float3 tangentX = float3(1, 0, 0);
                float3 tangentZ = float3(0, 0, 1);
                
                int maxWaves = min(MAX_WAVES, _MaxWaves);
                
                for (int i = 0; i < maxWaves; i++)
                {
                    float2 dir = _WaveDirs[i];
                    float wavelength = 0;
                    float amplitude = 0;
                    WaveDistribution(i, wavelength, amplitude);
                    float k = UNITY_PI / wavelength;
                    float speed = sqrt(baseSpeed * k);
                    float phase = k * dot(dir, posOS.xz) - speed * _Time.y;

                    float sinP = sin(phase);
                    float cosP = cos(phase);

                    float scale = pow(k, 2);
                    float suppression = pow(k, -1);
                    laplacian += amplitude * sin(phase) * scale * suppression;

                    float Qi = _WaveSteepness/ (k * amplitude * MAX_WAVES);
                    
                    float2 dPhase_dXZ = k * dir;

                    float dYdX = amplitude * cosP * dPhase_dXZ.x;
                    float dYdZ = amplitude * cosP * dPhase_dXZ.y;

                    float dXdX = -Qi * dir.x * amplitude * sinP * dPhase_dXZ.x;
                    float dZdX = -Qi * dir.y * amplitude * sinP * dPhase_dXZ.x;

                    float dXdZ = -Qi * dir.x * amplitude * sinP * dPhase_dXZ.y;
                    float dZdZ = -Qi * dir.y * amplitude * sinP * dPhase_dXZ.y;

                    tangentX += float3(dXdX, dYdX, dZdX);
                    tangentZ += float3(dXdZ, dYdZ, dZdZ);
                }
                float3 normalOS = normalize(cross(tangentZ, tangentX));
                
                return normalOS;
            }

            [domain("tri")]
            Interpolators domain(TessellationFactors f, OutputPatch<v2t, 3> patch, float3 bary : SV_DomainLocation)
            {
                Interpolators o;

                float3 objectPos =
                    patch[0].objectPos * bary.x +
                    patch[1].objectPos * bary.y +
                    patch[2].objectPos * bary.z;
                
                float3 worldPos = mul(unity_ObjectToWorld, float4(objectPos , 1.0)).xyz;

                float3 offset = GerstnerDisplace(
                    worldPos,
                    9.81
                );

                worldPos += offset;
                
                UNITY_INITIALIZE_OUTPUT(Interpolators, o);
                o.lodFade = unity_LODFade.y;
                float4 clipPos = UnityWorldToClipPos(worldPos);
                o.pos = clipPos;
                o.screenPos = ComputeScreenPos(clipPos);
                o.positionWS = worldPos;
                UNITY_TRANSFER_FOG(o,o.pos);
                TRANSFER_SHADOW_WPOS(o, worldPos);
 
                return o;
            }

            float3 RaymarchSSR_ViewSpace(
                float3 originWS,
                float3 normalWS,
                out bool hit
            )
            {
                if (_SSRSteps == 0) return 0;
                
                float3 originVS = mul(UNITY_MATRIX_V, float4(originWS, 1.0)).xyz;
                float3 viewDirVS = normalize(-originVS); 
                float3 normalVS = mul((float3x3)UNITY_MATRIX_V, normalWS);

                float3 reflDirVS = reflect(viewDirVS, normalVS);

                float3 currVS = originVS + reflDirVS * 0.1;
                float stepSize = _SSRStepSize;
                float thickness = _SSRThickness;
                int maxSteps = min(max(1, _SSRSteps), SSR_MAX_STEPS);

                for (int i = 0; i < maxSteps; i++)
                {
                    float4 clipPos = mul(UNITY_MATRIX_P, float4(currVS, 1.0));
                    float2 uv = (clipPos.xy / clipPos.w) * 0.5 + 0.5;

                    #if UNITY_UV_STARTS_AT_TOP
                        uv.y = 1.0 - uv.y;
                    #endif

                    if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1)
                        break;

                    float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
                    float sceneLinearZ = LinearEyeDepth(rawDepth);

                    float dz = abs(-currVS.z - sceneLinearZ);
                    if (dz < thickness)
                    {
                        hit = true;
                        return tex2D(_LastFrameColor, uv).rgb;
                    }
                    currVS += reflDirVS * stepSize;
                }
                return float3(0, 0, 0);
            }

            fixed4 frag(Interpolators i) : SV_Target
            {                
                float laplacian = 0;
                float3 normalWS = GerstnerNormalsAndCurvature(i.positionWS, 9.81, laplacian);
                float3 viewDir = normalize(i.positionWS - _WorldSpaceCameraPos);
                
                float shadow = SHADOW_ATTENUATION(i);

                float3 lightDir = _WorldSpaceLightPos0.xyz;

                float ndotl = saturate(dot(normalWS, lightDir));
                float backSSS = saturate(dot(normalWS, -lightDir)) * 0.4; 
                float wrap = ndotl * 0.5 + 0.5; 
                float transmission = pow(1.0 - saturate(dot(normalWS, viewDir)), 3.0);
                
                float3 reflection = reflect(viewDir, normalWS);
                float3 skyColorReflect = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflection, 0);

                float light = pow(saturate(dot(lightDir, float3(0,1,0))), .5);
                float3 sss = (backSSS * transmission * wrap) * _SSSColor * _LightColor0 * light;
                
                float NdotV = saturate(dot(normalWS, -viewDir));
                float3 F0 = lerp(float3(0.02, 0.02, 0.02), _Color, _Metallic);
                float3 fresnel = FresnelSchlick(NdotV, F0);
                float3 specular = PBRSpecular(normalWS, -viewDir, lightDir, _Color, _Metallic, _Roughness) * _LightColor0 * shadow;

                float foamAmount = saturate(laplacian - _FoamAmount) * _FoamStrength;
                
                float d = dot(lightDir, normalWS) * 0.5 + 0.5;
                float3 color = d * _Color * light;
                color *= lerp(1, .75, shadow);
                float fresnelFactor = dot(fresnel, float3(0.333,0.333,0.333));

                bool ssrHit;
                float3 ssrColor = RaymarchSSR_ViewSpace(
                    i.positionWS,
                    reflection,
                    ssrHit
                );
                float blend = ssrHit ? 1.0 : 0.0;
                skyColorReflect = lerp(skyColorReflect, ssrColor, blend * fresnel);
                color = lerp(lerp(sss + color, skyColorReflect, fresnelFactor), float3(1,1,1), saturate(foamAmount));
                //return float4(ssrColor, 1);

                float transparency = dot(specular, float3(0.333,0.333,0.333));
                transparency = lerp(saturate(max(transparency, fresnelFactor) * _Transparency), 1, saturate(foamAmount));
                #ifdef LOD_FADE_CROSSFADE
                    transparency *= (sqrt(1-i.lodFade)); 
                #endif
                
                float3 finalColor = saturate(specular + color);
                UNITY_APPLY_FOG(i.fogCoord, finalColor);
                //return float4(shadow.xxx,1);
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
            #pragma hull hull
            #pragma domain domain
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "Helper.cginc"

            float _WaveStrength, _WaveLength, _WaveSteepness, _TessFactor, _FoamStrength, _FoamAmount, _Transparency;
            float _WaveStrengthDistribution, _WaveLengthDistribution, _MaxWaves;

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
            };

            struct Interpolators
            {
                float4 pos : SV_POSITION;
            };

            struct TessellationFactors
            {
                float edge[3] : SV_TessFactor;
                float inside  : SV_InsideTessFactor;
            };

            v2t vert(appdata v)
            {
                v2t o;
                o.objectPos = v.vertex.xyz;
                return o;
            }

            [domain("tri")]
            [outputcontrolpoints(3)]
            [outputtopology("triangle_cw")]
            [patchconstantfunc("PatchConstantFunction")]
            [partitioning("fractional_even")]
            v2t hull(InputPatch<v2t, 3> patch, uint id : SV_OutputControlPointID)
            {
                return patch[id];
            }

            TessellationFactors PatchConstantFunction(InputPatch<v2t, 3> patch)
            {
                TessellationFactors f;
                f.edge[0] = _TessFactor;
                f.edge[1] = _TessFactor;
                f.edge[2] = _TessFactor;
                f.inside  = _TessFactor;

                return f;
            }

            void WaveDistribution(int i, inout float waveLength, inout float waveAmplitude)
            {
                waveLength = _WaveLength / pow(_WaveLengthDistribution, i);
                waveAmplitude = _WaveStrength / pow(_WaveStrengthDistribution, i);
            }

            float3 GerstnerDisplace(
                float3 posOS,
                float baseSpeed
            )
            {
                float3 totalOffset = float3(0, 0, 0);

                int maxWaves = min(MAX_WAVES, _MaxWaves);
                
                for (int i = 0; i < maxWaves; i++)
                {
                    float2 dir = _WaveDirs[i];
                    float wavelength = 0;
                    float amplitude = 0;
                    WaveDistribution(i, wavelength, amplitude);
                    float k = UNITY_PI / wavelength;
                    float speed = sqrt(baseSpeed * k);
                    float phase = k * dot(dir, posOS.xz) - speed * _Time.y;

                    float sinP = sin(phase);
                    float cosP = cos(phase);

                    float Qi = _WaveSteepness / (k * amplitude * MAX_WAVES);

                    totalOffset.x += Qi * dir.x * amplitude * cosP;
                    totalOffset.z += Qi * dir.y * amplitude * cosP;
                    totalOffset.y += amplitude * sinP;
                }
                
                return totalOffset;
            }

            [domain("tri")]
            Interpolators domain(TessellationFactors f, OutputPatch<v2t, 3> patch, float3 bary : SV_DomainLocation)
            {
                Interpolators o;

                float3 objectPos =
                    patch[0].objectPos * bary.x +
                    patch[1].objectPos * bary.y +
                    patch[2].objectPos * bary.z;
                
                float3 worldPos = mul(unity_ObjectToWorld, float4(objectPos , 1.0)).xyz;

                float3 offset = GerstnerDisplace(
                    worldPos,
                    9.81
                );

                worldPos += offset;
                
                UNITY_INITIALIZE_OUTPUT(Interpolators, o);
                o.pos = UnityWorldToClipPos(worldPos);

                return o;
            }

            fixed4 frag(Interpolators i) : SV_Target
            {
                SHADOW_CASTER_FRAGMENT(i)
            }
            ENDCG
        }
    }
    FallBack Off
}