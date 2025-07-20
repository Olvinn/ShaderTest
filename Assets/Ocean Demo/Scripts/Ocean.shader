Shader "Custom/Water_Clean_WithNormals"
{
    Properties
    {
        _Color ("Color", Color) = (0, 0.5, 1, 1)
        _WaveStrength ("Wave Strength", Float) = 0.2
        _TessFactor ("Tessellation Factor", Float) = 3
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

            float4 _Color;
            float _WaveStrength, _TessFactor;

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

            void displace(inout float3 objectPos, out float3 normalOS)
            {
                float2 dir = normalize(float2(0.5, 0.5));
                float phase = dot(objectPos.xz, dir) + _Time.y;
                float wave = sin(phase) * _WaveStrength;
                objectPos.y = wave;

                float slope = cos(phase) * _WaveStrength;
                float3 tangent = float3(1, slope * dir.x, 0);
                float3 bitangent = float3(0, slope * dir.y, 1);
                normalOS = normalize(cross(bitangent, tangent));
            }

            float3 displace(float3 objectPos)
            {
                float2 dir = normalize(float2(0.5, 0.5));
                float phase = dot(objectPos.xz, dir) + _Time.y;
                float wave = sin(phase) * _WaveStrength;
                objectPos.y = wave;
                return objectPos;
            }

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

            float4 WorldToClip(float3 worldPos)
            {
                return mul(UNITY_MATRIX_VP, float4(worldPos, 1.0));
            }

            float TessFactorForEdge(float3 a, float3 b)
            {
                float3 mid = (displace(a) + displace(b)) * 0.5;
                float dist = distance(_WorldSpaceCameraPos, mid);
                
                return lerp(10, 1, saturate(dist / _TessFactor));
            }

            TessellationFactors PatchConstantFunction(InputPatch<v2t, 3> patch)
            {
                float3 wp0 = mul(unity_ObjectToWorld, float4(patch[0].objectPos, 1)).xyz;
                float3 wp1 = mul(unity_ObjectToWorld, float4(patch[1].objectPos, 1)).xyz;
                float3 wp2 = mul(unity_ObjectToWorld, float4(patch[2].objectPos, 1)).xyz;
                
                float e0 = TessFactorForEdge(wp0, wp1);
                float e1 = TessFactorForEdge(wp1, wp2);
                float e2 = TessFactorForEdge(wp2, wp0);
                
                TessellationFactors f;
                f.edge[0] = e0;
                f.edge[1] = e1;
                f.edge[2] = e2;
                f.inside = min(min(e0, e1), e2);

                return f;
            }

            [domain("tri")]
            Interpolators domain(TessellationFactors f, OutputPatch<v2t, 3> patch, float3 bary : SV_DomainLocation)
            {
                Interpolators o;

                float3 objectPos =
                    patch[0].objectPos * bary.x +
                    patch[1].objectPos * bary.y +
                    patch[2].objectPos * bary.z;

                float3 normalOS;
                displace(objectPos, normalOS);

                float3 worldPos = mul(unity_ObjectToWorld, float4(objectPos, 1.0)).xyz;
                o.positionCS = UnityWorldToClipPos(worldPos);
                o.worldPos = worldPos;
                o.normalOS = normalOS;

                return o;
            }

            fixed4 frag(Interpolators i) : SV_Target
            {
                float3 normalWS = UnityObjectToWorldNormal(i.normalOS);
                float d = dot(_WorldSpaceLightPos0.xyz, normalWS) * 0.5 + 0.5;
                float3 color = _Color.rgb * d;
                return float4(color, 1);
            }
            ENDCG
        }
    }
    FallBack Off
}