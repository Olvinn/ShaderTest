Shader "Unlit/SimpleLit"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _SpecPow ("Specular Power", Range(1, 256)) = 1
        _SpecInt ("Specular Intensity", Range(0,1)) = .5
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            Tags { "LightMode"="ForwardBase"} 
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 worldNormal : TEXCOORD1;
                float3 vertexWorld : TEXCOORD2;
            };

            float4 _Color;
            float4 _MainTex_ST;
            float _SpecPow;
            float _SpecInt;

            v2f vert (appdata v)
            {
                v2f o;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.worldNormal =  UnityObjectToWorldNormal(v.normal);
                o.vertexWorld = mul(unity_ObjectToWorld, v.vertex).xyz;
                return o;
            }

            float3 LambertShading(float3 colorRefl, float3 normal, float3 lightDir)
            {
                return colorRefl * max(0, dot(normal, lightDir));
            }

            float3 PhongShading(float3 colorRefl, float power, float3 normal, float3 lightDir, float3 viewDir)
            {
                float3 h = normalize(lightDir + viewDir);
                
                return colorRefl * pow(max(0, dot(normal, h)), power);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float4 col = _Color;
                float3 diffuse = LambertShading(_LightColor0.rgb, i.worldNormal, _WorldSpaceLightPos0.xyz);
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.vertexWorld);
                float3 specular = PhongShading(_LightColor0.rgb, _SpecPow, i.worldNormal, _WorldSpaceLightPos0.xyz, viewDir);
                half3 reflectWorld = reflect(-viewDir, i.worldNormal);
                half3 ambientData = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflectWorld);
                half3 ambient = DecodeHDR(half4(ambientData, 1), unity_SpecCube0_HDR);
                col.rgb *= lerp(unity_IndirectSpecColor, ambient, _SpecInt) + diffuse + specular * _SpecInt;
                return col;
            }
            ENDCG
        }
    }
}
