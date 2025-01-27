// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/WaterShaderRefined"
{
    Properties
    {
        _Normal ("Normal Map", 2D) = "Normal" {}
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderQueue"="Transparent" }
        LOD 200
        ZWrite On
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "UnityStandardUtils.cginc"
            #include "UnityLightingCommon.cginc"

            struct appdata
            {
                half4 vertex : POSITION;
                half3 normal : NORMAL;
                half4 tangent : TANGENT;
                half2 uv : TEXCOORD0;
            };

            struct v2f
            {
                half4 position : POSITION;
                half2 uv : TEXCOORD0;
                half3 worldPos : TEXCOORD2;
                half3 worldNormal : TEXCOORD3;
                half4 worldTangent : TEXCOORD4;
                UNITY_FOG_COORDS(1)
            };

            sampler2D _Normal;
            half4 _Normal_ST;
            half4 _MainColor;
            half _WaveSpeed, _NormalPow;
            half _ReflectionStrength;

            v2f vert(appdata v)
            {
                v2f o;
	            o.position = UnityObjectToClipPos(v.vertex);
	            o.worldPos = mul(unity_ObjectToWorld, v.vertex);
	            o.worldNormal = UnityObjectToWorldNormal(v.normal);
	            o.worldTangent = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
	            o.uv = TRANSFORM_TEX(v.uv, _Normal);

                UNITY_TRANSFER_FOG(o, o.position);
                return o;
            }

            float3 PhongShading(float3 colorRefl, float3 normal, float3 lightDir, float3 viewDir)
            {
                float3 h = normalize(lightDir + viewDir);
                
                return colorRefl * pow(max(0, dot(normal, h)), 16);
            }

            half Fresnel(half3 normal, half3 viewDir, half strength)
            {
                return clamp(1 - pow(dot(normal, viewDir), strength), 0, 4);
            }
            
            half3 ObjectScale()
            {
                return half3(
                    length(unity_ObjectToWorld._m00_m10_m20),
                    length(unity_ObjectToWorld._m01_m11_m21),
                    length(unity_ObjectToWorld._m02_m12_m22)
                );
            }

            half4 frag(v2f i) : SV_Target
            {
	            float3 normal = UnpackScaleNormal(tex2D(_Normal, i.uv.xy), 1);
	            normal = normal.xzy;
	            float3 binormal = cross(i.worldNormal, i.worldTangent.xyz) * i.worldTangent.w;
                normal = normalize(
		            normal.x * i.worldTangent +
		            normal.y * i.worldNormal +
		            normal.z * binormal
	            );
                
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos.xyz);
                float3 reflectWorld = reflect(-viewDir, normal);
                float3 ambientData = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflectWorld, 0);
                half3 ambient = DecodeHDR(half4(ambientData, 1), unity_SpecCube0_HDR);
                half4 col = half4(1, 1, 1, 1);
                float3 specular = PhongShading(_LightColor0.rgb, normal, _WorldSpaceLightPos0.xyz, viewDir);
                col.rgb *= lerp(unity_IndirectSpecColor, ambient, Fresnel(normal, viewDir, 128)) + specular * 2;
                col = saturate(col);
                
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
}
