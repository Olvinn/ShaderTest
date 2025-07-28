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
        
        ZWrite On
        ZTest LEqual

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
                float3 normal : TEXCOORD1;
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
                o.normal =  v.normal;
                o.vertexWorld = mul(unity_ObjectToWorld, v.vertex).xyz;
                // TRANSFER_SHADOW_CASTER_NORMALOFFSET(o.vertexWorld)
                return o;
            }

            float3 LambertShading(float3 colorRefl, float3 normal, float3 lightDir)
            {
                return colorRefl * max(0, dot(normal, lightDir));
            }

            float3 PhongShading(float3 colorRefl, float3 normal, float3 lightDir, float3 viewDir)
            {
                float3 h = normalize(lightDir + viewDir);
                
                return colorRefl * pow(max(0, dot(normal, h)), _SpecPow);
            }

            float Fresnel(float3 normal, float3 viewDir, float strength)
            {
                return clamp(1 - pow(dot(normal, viewDir), strength), 0, 1);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float4 col = _Color;
                float3 worldNormal =  UnityObjectToWorldNormal(i.normal);
                float3 diffuse = LambertShading(_LightColor0.rgb, worldNormal, _WorldSpaceLightPos0.xyz);
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.vertexWorld.xyz);
                float3 specular = PhongShading(_LightColor0.rgb, worldNormal, _WorldSpaceLightPos0.xyz, viewDir);
                float3 reflectWorld = reflect(-viewDir, worldNormal);
                float3 ambientData = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflectWorld, 0);
                half3 ambient = DecodeHDR(half4(ambientData, 1), unity_SpecCube0_HDR);
                col.rgb *= lerp(unity_IndirectSpecColor, ambient, Fresnel(worldNormal, viewDir, _SpecInt)) + diffuse + specular * _SpecInt;
                return col;
            }
            ENDCG
        }
    }
    Fallback "Legacy Shaders/Transparent/Cutout/VertexLit"
}
