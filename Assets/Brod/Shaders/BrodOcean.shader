Shader "Brod/Ocean"
{
    Properties
    {
        [Header(Details Normal)]
        _NormalMap ("Normal Map", 2D) = "white" {}
        _NormalsPower ("Normals Power", Range(0,1)) = .5
        
        [Header(Water Volume)]
        _WaterAbsorption ("Absorption", Color) = (0.45, 0.06, 0.01, 0)
        _WaterScatter    ("Scatter",    Color) = (0.02, 0.05, 0.08, 0)
        
        [Header(Foam)]
        _FoamTexture    ("Foam Texture",    2D)             = "white" {}
        _FoamNormal     ("Foam Normal",     2D)             = "white" {}
        _FoamAmount     ("Foam Amount",     Float)          = 1
        _FoamStrength   ("Foam Strength",   Float)          = 1
        _FoamNormalsPower ("Foam normals power", Range(0,1)) = .5
        
        [Header(Shading)]
        _Transparency   ("Transparency",    Range(0, 1000))    = 0
        _MaxWaves       ("Max Waves",       Range(1, 128))   = 64
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
        
        [Header(Tesselation)]
        _TessMin  ("Tess Min",           Range(1, 4))   = 1
        _TessMax  ("Tess Max",           Range(4, 64))  = 32
        _TessNear ("Tess Near Distance", Float)         = 5
        _TessFar  ("Tess Far Distance",  Float)         = 80
        
        [Toggle] _FogBlend  ("Blend in Fog", Int) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType"     = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "RenderQueue"    = "Geometry+100"
        }

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }

            Cull Off

            HLSLPROGRAM
            // ── Defines ──
            #pragma target 5.0
            #pragma vertex   vert
            #pragma hull     hull
            #pragma domain   domain
            #pragma fragment frag
            #pragma require  tessellation tessHW

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

            #define SSR_MAX_STEPS   64
            #define IOR_AIR_WATER   0.75 

            // ── Variables ──
            TEXTURE2D_X(_FoamTexture);              SAMPLER(sampler_FoamTexture);
            TEXTURE2D_X(_FoamNormal);               SAMPLER(sampler_FoamNormal);
            TEXTURE2D_X(_NormalMap);                SAMPLER(sampler_NormalMap);
            TEXTURE2D_X(_CameraOpaqueTexture);      SAMPLER(sampler_CameraOpaqueTexture);
            TEXTURE2D_X_FLOAT(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);
            
            TEXTURE2D(_LocalWaterDetailsA);        SAMPLER(sampler_LocalWaterDetailsA);
            TEXTURE2D(_LocalWaterDetailsB);        SAMPLER(sampler_LocalWaterDetailsB);
            TEXTURE2D(_LocalWaterDetailsC);        SAMPLER(sampler_LocalWaterDetailsC);
            TEXTURE2D(_LocalWaterDetailsD);        SAMPLER(sampler_LocalWaterDetailsD);

            CBUFFER_START(UnityPerMaterial)
                float4 _WaterAbsorption, _WaterScatter, _FoamTexture_ST, _NormalMap_ST;
            
                float2 _MapCenterWSA, _MapSizeWSA;
                float2 _MapCenterWSB, _MapSizeWSB;
                float2 _MapCenterWSC, _MapSizeWSC;
                float2 _MapCenterWSD, _MapSizeWSD;
            
                half   _FoamAmount, _FoamStrength, _Transparency, _NormalsPower, _FoamNormalsPower;
                half   _Metallic, _Roughness;
                int    _MaxWaves, _FogBlend;

                half   _SSRThickness, _SSRStepSize, _StepPropagation;
                int    _SSRSteps;

                half  _SSSStrength, _SSSDirectionality, _SSSThicknessPower, _SSSAmbient;
                float _MaxWaveAmplitude;

                half _TessMin, _TessMax, _TessNear, _TessFar, _MaxDisp;
            CBUFFER_END
            
            // ── Structs ──
            struct Attributes
            {
                float4 vertex : POSITION;
                half2  uv     : TEXCOORD0;
            };
            
            struct ControlPoint
            {
                float3 positionWS : TEXCOORD0;
                float2 uv         : TEXCOORD1;
            };

            struct TessFactors
            {
                float edge[3] : SV_TessFactor;
                float inside  : SV_InsideTessFactor;
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
            
            float2 BrodOcean_GetCascadeCenter(int cascade)
            {
                switch (cascade)
                {
                    default:
                    case 0: return _MapCenterWSA;
                    case 1: return _MapCenterWSB;
                    case 2: return _MapCenterWSC;
                    case 3: return _MapCenterWSD;
                }
            }
            
            float2 BrodOcean_GetCascadeSize(int cascade)
            {
                switch (cascade)
                {
                    default:
                    case 0: return _MapSizeWSA;
                    case 1: return _MapSizeWSB;
                    case 2: return _MapSizeWSC;
                    case 3: return _MapSizeWSD;
                }
            }
            
            // ── Helper Functions ──
            int BrodOcean_CalculateDetailsCascade(float2 worldXZ)
            {
                if ((worldXZ.x < _MapCenterWSD.x + _MapSizeWSD.x * .5) &&
                    (worldXZ.x > _MapCenterWSD.x - _MapSizeWSD.x * .5) &&
                    (worldXZ.y < _MapCenterWSD.y + _MapSizeWSD.y * .5) &&
                    (worldXZ.y > _MapCenterWSD.y - _MapSizeWSD.y * .5))
                    return 3;
                if ((worldXZ.x < _MapCenterWSC.x + _MapSizeWSC.x * .5) &&
                    (worldXZ.x > _MapCenterWSC.x - _MapSizeWSC.x * .5) &&
                    (worldXZ.y < _MapCenterWSC.y + _MapSizeWSC.y * .5) &&
                    (worldXZ.y > _MapCenterWSC.y - _MapSizeWSC.y * .5))
                    return 2;
                if ((worldXZ.x < _MapCenterWSB.x + _MapSizeWSB.x * .5) &&
                    (worldXZ.x > _MapCenterWSB.x - _MapSizeWSB.x * .5) &&
                    (worldXZ.y < _MapCenterWSB.y + _MapSizeWSB.y * .5) &&
                    (worldXZ.y > _MapCenterWSB.y - _MapSizeWSB.y * .5))
                    return 1;
                return 0;
            }
            
            float3 BrodOcean_ReadDetailsHeight(float2 worldXZ)
            {
                int cascade = BrodOcean_CalculateDetailsCascade(worldXZ);
                float2 uv = (worldXZ - BrodOcean_GetCascadeCenter(cascade)) / BrodOcean_GetCascadeSize(cascade) + 0.5;
                float4 packed = 0; 
                if (cascade == 3)
                    packed = SAMPLE_TEXTURE2D_LOD(_LocalWaterDetailsD, sampler_LocalWaterDetailsD, uv, 0);
                else if (cascade == 2)
                    packed = SAMPLE_TEXTURE2D_LOD(_LocalWaterDetailsC, sampler_LocalWaterDetailsC, uv, 0);
                else if (cascade == 1)
                    packed = SAMPLE_TEXTURE2D_LOD(_LocalWaterDetailsB, sampler_LocalWaterDetailsB, uv, 0);
                else if (cascade == 0)
                    packed = SAMPLE_TEXTURE2D_LOD(_LocalWaterDetailsA, sampler_LocalWaterDetailsA, uv, 0);
                return packed.b;
            }

            float3 BrodOcean_ReadDetailsNormal(float2 worldXZ)
            {
                int cascade = BrodOcean_CalculateDetailsCascade(worldXZ);
                float2 uv = (worldXZ - BrodOcean_GetCascadeCenter(cascade)) / BrodOcean_GetCascadeSize(cascade) + 0.5;
                float4 packed = 0; 
                if (cascade == 3)
                    packed = SAMPLE_TEXTURE2D(_LocalWaterDetailsD, sampler_LocalWaterDetailsD, uv);
                else if (cascade == 2)
                    packed = SAMPLE_TEXTURE2D(_LocalWaterDetailsC, sampler_LocalWaterDetailsC, uv);
                else if (cascade == 1)
                    packed = SAMPLE_TEXTURE2D(_LocalWaterDetailsB, sampler_LocalWaterDetailsB, uv);
                else if (cascade == 0)
                    packed = SAMPLE_TEXTURE2D(_LocalWaterDetailsA, sampler_LocalWaterDetailsA, uv);
                return normalize(float3(-packed.r, 1, -packed.g));
            }

            float BrodOcean_ReadFoam(float2 worldXZ)
            {
                int cascade = BrodOcean_CalculateDetailsCascade(worldXZ);
                float2 uv = (worldXZ - BrodOcean_GetCascadeCenter(cascade)) / BrodOcean_GetCascadeSize(cascade) + 0.5;
                if (cascade == 0)
                    return SAMPLE_TEXTURE2D(_LocalWaterDetailsA, sampler_LocalWaterDetailsA, uv).a;
                if (cascade == 1)
                    return SAMPLE_TEXTURE2D(_LocalWaterDetailsB, sampler_LocalWaterDetailsB, uv).a;
                if (cascade == 2)
                    return SAMPLE_TEXTURE2D(_LocalWaterDetailsC, sampler_LocalWaterDetailsC, uv).a;
                if (cascade == 3)
                    return SAMPLE_TEXTURE2D(_LocalWaterDetailsD, sampler_LocalWaterDetailsD, uv).a;
                return 0;
            }

            float BrodOcean_HenyeyGreenstein(float cosTheta, float g)
            {
                float g2 = g * g;
                float d  = 1.0 + g2 - 2.0 * g * cosTheta;
                return (1.0 - g2) / (4.0 * PI * pow(d, 1.5));
            }

            half3 BrodOcean_WaterSSS(float3 viewDir, float3 normal, Light light,
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

                float  phase      = BrodOcean_HenyeyGreenstein(dot(light.direction, viewDir), 0.5);
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
            
            float BrodOcean_EdgeTessFactor(float3 p0WS, float3 p1WS)
            {
                float3 mid  = (p0WS + p1WS) * 0.5;
                float  dist = distance(mid, _WorldSpaceCameraPos);
                float  t    = saturate((dist - _TessNear) / (_TessFar - _TessNear));
                return max(1.0, lerp(_TessMax, _TessMin, t));
            }
            
            bool BrodOcean_FrustumCull(float3 p0, float3 p1, float3 p2)
            {
                float4 c0 = TransformWorldToHClip(p0);
                float4 c1 = TransformWorldToHClip(p1);
                float4 c2 = TransformWorldToHClip(p2);

                float bias = _MaxDisp;
                c0.w += bias;
                c1.w += bias;
                c2.w += bias;

                if(c0.x < -c0.w && c1.x < -c1.w && c2.x < -c2.w) return true; // left
                if(c0.x >  c0.w && c1.x >  c1.w && c2.x >  c2.w) return true; // right
                if(c0.y < -c0.w && c1.y < -c1.w && c2.y < -c2.w) return true; // bottom
                if(c0.y >  c0.w && c1.y >  c1.w && c2.y >  c2.w) return true; // top
                if(c0.z <  0    && c1.z <  0    && c2.z <  0   ) return true; // near
                if(c0.z >  c0.w && c1.z >  c1.w && c2.z >  c2.w) return true; // far

                return false;
            }
            
            TessFactors BrodOcean_PatchConstant(InputPatch<ControlPoint, 3> patch)
            {
                TessFactors f;

                if(BrodOcean_FrustumCull(patch[0].positionWS, patch[1].positionWS, patch[2].positionWS))
                {
                    f.edge[0] = f.edge[1] = f.edge[2] = f.inside = 0;
                    return f;
                }

                f.edge[0] = BrodOcean_EdgeTessFactor(patch[1].positionWS, patch[2].positionWS);
                f.edge[1] = BrodOcean_EdgeTessFactor(patch[2].positionWS, patch[0].positionWS);
                f.edge[2] = BrodOcean_EdgeTessFactor(patch[0].positionWS, patch[1].positionWS);

                f.inside  = max(f.edge[0], max(f.edge[1], f.edge[2]));

                return f;
            }

            // ── Main Functions ──
            ControlPoint vert(Attributes IN)
            {
                ControlPoint OUT;
                OUT.positionWS = TransformObjectToWorld(IN.vertex.xyz);
                OUT.uv         = IN.uv;
                return OUT;
            }
            
            [domain("tri")]
            [partitioning("fractional_even")]
            [outputtopology("triangle_cw")]
            [outputcontrolpoints(3)]
            [patchconstantfunc("BrodOcean_PatchConstant")]
            ControlPoint hull(InputPatch<ControlPoint, 3> patch,
                              uint id : SV_OutputControlPointID)
            {
                return patch[id];
            }
            
            [domain("tri")]
            Varyings domain(TessFactors factors, OutputPatch<ControlPoint, 3> patch, float3 bary : SV_DomainLocation)
            {
                float3 posWS = patch[0].positionWS * bary.x
                             + patch[1].positionWS * bary.y
                             + patch[2].positionWS * bary.z;
                float2 uv    = patch[0].uv * bary.x
                             + patch[1].uv * bary.y
                             + patch[2].uv * bary.z;
                
                Varyings OUT = (Varyings)0;

                OUT.initialWS = posWS;

                float3 normal, tangent;
                
                float  dist = distance(posWS, _WorldSpaceCameraPos);
                int maxWaves = max(1, (1 - saturate(dist / _TessFar)) * _MaxWaves);
                float3 offset = BrodGerstner_GetOffset(posWS.xz, _Time.y, maxWaves, normal, tangent);
                posWS += offset;
                half3 sec = BrodOcean_ReadDetailsHeight(posWS.xz);
                posWS.y += sec;

                float4 clipPos    = TransformWorldToHClip(posWS);
                OUT.positionCS    = clipPos;
                OUT.positionSS    = ComputeScreenPos(clipPos);
                OUT.positionWS    = posWS;
                OUT.uv            = uv;
                OUT.fog           = ComputeFogFactor(clipPos.z);
                OUT.normalWS      = normalize(normal);
                OUT.tangentWS     = normalize(tangent);
                OUT.bitangentWS   = cross(OUT.normalWS, OUT.tangentWS);
                return OUT;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3x3 TBN   = float3x3(i.tangentWS, i.bitangentWS, i.normalWS);
                float4 packed1 = SAMPLE_TEXTURE2D(_NormalMap,
                                                  sampler_NormalMap, i.initialWS.xz * _NormalMap_ST.xy + _Time.y * .25);
                float4 packed2 = SAMPLE_TEXTURE2D(_NormalMap,
                                                  sampler_NormalMap, i.initialWS.xz * _NormalMap_ST.xy * 1.3f - _Time.y * .5);
                float3 normalTS = lerp(UnpackNormal(packed1), UnpackNormal(packed2), .5);
                normalTS.xy *= _NormalsPower;
                normalTS = normalize(normalTS);
                float  jacobian = 0;
                float3 normal = mul(normalTS, TBN); 
                float  dist = distance(i.initialWS, _WorldSpaceCameraPos);
                half t = 1 - saturate(dist / (_TessFar * 2));
                int maxWaves = max(8, t * _MaxWaves * .5);
                BrodGerstner_GetNormalJacobian(i.initialWS.xz, _Time.y, maxWaves, normal, jacobian);
                jacobian = saturate((jacobian - .9) * 10);
                jacobian = max(jacobian, BrodOcean_ReadFoam(i.initialWS.xz));
                normal += BrodOcean_ReadDetailsNormal(i.positionWS.xz);
                
                half foamMask   = SAMPLE_DEPTH_TEXTURE(_FoamTexture, sampler_FoamTexture,
                                    i.initialWS.xz * _FoamTexture_ST.xy
                                  + _FoamTexture_ST.zw);
                float4 foamNormal = SAMPLE_TEXTURE2D(_FoamNormal, sampler_FoamNormal,
                                    i.initialWS.xz * _FoamTexture_ST.xy
                                  + _FoamTexture_ST.zw);
                
                half foamAmount = saturate((foamMask - (1 - jacobian) + _FoamAmount) * _FoamStrength);
                
                float3 foamNormalUnpacked = UnpackNormal(foamNormal);
                foamNormalUnpacked.xy *= _FoamNormalsPower;
                normal = lerp(normal, mul(foamNormalUnpacked, TBN), foamAmount);
                normal = normalize(normal);

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

                float fresnel = Brod_FresnelSchlickWater(viewDir, normal);

                float3 envReflection = Brod_CubemapAmbient(reflDir, 0);
                #ifdef SSR
                    bool   ssrHit;
                    half3  ssrReflection = Brod_RaymarchSSReflection(
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
                half3 sss = BrodOcean_WaterSSS(viewDir, normal, mainLight, jacobian, waveDisplacement);  
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
                half3 unerwaterCol = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, refrUV).rgb;
                unerwaterCol = lerp(unerwaterCol, Brod_CubemapAmbient(refrDir, 0), isSky);

                half3 sigmaT      = (1 - _WaterAbsorption.rgb) +  (1 - _WaterScatter.rgb);
                half3 depthTint   = exp(-sigmaT * length(underWS - i.positionWS) / _Transparency);
                unerwaterCol = unerwaterCol * (isSky ? 0 : depthTint);
                                
                half3 specular = Brod_PBRSpecular(normal, -viewDir, mainLight.direction,
                                                sss, _Metallic, _Roughness)
                               * mainLight.color
                               * mainLight.shadowAttenuation
                               * (1 - foamAmount);

                float3 transmitted = unerwaterCol * (1.0 - fresnel);
                float3 waterColor  = reflection * fresnel + transmitted;

                float  NdotL      = saturate(dot(normal, mainLight.direction));
                float3 foamDiffuse = (foamMask * mainLight.color + SampleSH(normal))
                                   * max(0.75, mainLight.shadowAttenuation) * (NdotL * .5 + .5);
                float3 finalColor  = lerp(waterColor, foamDiffuse, foamAmount);

                finalColor += specular * (1.0 - foamAmount) + sss;
                
                //finalColor = MixFog(finalColor, i.fog);
                if (_FogBlend)
                    return half4(lerp(finalColor, Brod_CubemapAmbient(viewDir, 0), saturate(i.fog)), 1);
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
            Cull Front

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
                float3 _LightDirection;
                float3 _LightPosition;
            CBUFFER_END

            struct ShadowAttributes { float4 vertex : POSITION; float3 normal : NORMAL; };
            struct ShadowVaryings   { float4 positionCS : SV_POSITION; };

            ShadowVaryings shadowVert(ShadowAttributes IN)
            {
                ShadowVaryings OUT;

                float3 worldPos = mul(unity_ObjectToWorld, float4(IN.vertex.xyz, 1)).xyz;
                float3 normalWS, tangentWS;

                float3 offset = BrodGerstner_GetOffset(worldPos.xz, _Time.y, _MaxWaves, normalWS, tangentWS);
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