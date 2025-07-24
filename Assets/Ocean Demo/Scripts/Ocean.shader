Shader "Custom/Ocean"
{
    Properties
    {
        _Color ("Color", Color) = (0, 0.5, 1, 1)
        _SSSColor ("SSS Color", Color) = (0, 0.5, 1, 1)
        _WaveStrength ("Wave Strength", Float) = 0.2
        _WaveLength ("Wave Length", Float) = 2
        _WaveSteepness ("Wave Steepness", Float) = .8
        _FoamStrength ("Foam", Float) = 1
        _TessFactor ("Tessellation Factor", Float) = 3
        _Metallic ("Metallic", Range(0,1)) = .5
        _Roughness ("Roughness", Range(0,1)) = .5
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 200

        Pass
        {
            CGPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma hull hull
            #pragma domain domain
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "Helper.cginc"

            float4 _Color, _SSSColor;
            float _WaveStrength, _WaveLength, _WaveSteepness, _TessFactor, _FoamStrength;
            float _Metallic, _Roughness;

            #define MAX_WAVES 64
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
                float4 positionCS : SV_POSITION;
                float3 worldPos   : TEXCOORD0;
                float3 normalOS   : TEXCOORD1;
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
                f.inside = _TessFactor;

                return f;
            }

            float3 GerstnerDisplaceWithNormals(
                float2 xzPos,
                float time,
                float baseAmp,
                float baseWL,
                float baseSpeed,
                float steepness,
                inout float3 normalOS
            )
            {
                float3 totalOffset = float3(0, 0, 0);
                float3 tangentX = float3(1, 0, 0);
                float3 tangentZ = float3(0, 0, 1);

                

                for (int i = 0; i < MAX_WAVES; i++)
                {
                    float2 dir = _WaveDirs[i];
                    float wavelength = baseWL / pow(1.15, i);
                    float amplitude = baseAmp / pow(1.25, i);
                    float k = UNITY_PI / wavelength;
                    float speed = sqrt(baseSpeed * k);
                    float phase = k * dot(dir, xzPos) - speed * time;

                    float sinP = sin(phase);
                    float cosP = cos(phase);

                    float Qi = steepness / (k * amplitude * MAX_WAVES); // stability fix

                    // Displacement
                    totalOffset.x += Qi * dir.x * amplitude * cosP;
                    totalOffset.z += Qi * dir.y * amplitude * cosP;
                    totalOffset.y += amplitude * sinP;
                    
                    //float2 displacementXZ = Qi * dir * amplitude * cosP;
                    //totalXZ += displacementXZ;

                    // Partial derivatives (∂P/∂x and ∂P/∂z)
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

                //totalXZ /= MAX_WAVES;
                //totalOffset.x = totalXZ.x;
                //totalOffset.z = totalXZ.y;
                normalOS = normalize(cross(tangentZ, tangentX));
                
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

                float3 normalOS = float3(0,1,0);
                float3 offset = GerstnerDisplaceWithNormals(
                    worldPos.xz,
                    _Time.y,
                    _WaveStrength,  
                    _WaveLength,
                    9.81,
                    _WaveSteepness,
                    normalOS
                );

                worldPos += offset;
                
                o.positionCS = UnityWorldToClipPos(worldPos);
                o.worldPos = worldPos;
                o.normalOS = normalOS;

                return o;
            }

            fixed4 frag(Interpolators i) : SV_Target
            {
                float3 normalWS = UnityObjectToWorldNormal(i.normalOS);
                float3 viewDir = normalize(i.worldPos - _WorldSpaceCameraPos);

                float3 lightDir = _WorldSpaceLightPos0.xyz;

                float ndotl = saturate(dot(normalWS, lightDir));
                float backSSS = saturate(dot(normalWS, -lightDir)) * 0.4; // fake backscatter
                float wrap = ndotl * 0.5 + 0.5; // wrap lighting
                float transmission = pow(1.0 - saturate(dot(normalWS, viewDir)), 3.0);

                float3 sss = (backSSS * transmission * wrap) * _SSSColor * _LightColor0;
                
                float3 reflection = reflect(viewDir, normalWS);
                float4 skyColorReflect = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflection, 0);

                float3 fresnel = FresnelSchlick(saturate(dot(normalWS, -viewDir)), lerp(float3(0.04, 0.04, 0.04), _Color, _Metallic));
                float3 specular = PBRSpecular(normalWS, -viewDir, lightDir, _Color, _Metallic, _Roughness);
                
                float d = dot(lightDir, normalWS) * 0.5 + 0.5;
                float3 color = d * _Color;
                color = lerp(sss + color, skyColorReflect, fresnel);

                //return float4(sss, 1);
                return float4(saturate(max(specular, color)), 1);
            }
            ENDCG
        }
    }
    FallBack Off
}