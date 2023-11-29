Shader "Unlit/Hologram"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _Gaps ("Gaps", float) = 1
        _Speed ("Speed", float) = 1
        _Curvature ("Curvature", float) = .05
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderQueue"="Transparent" }
        Cull Off
        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 worldNormal : TEXCOORD0;
                float3 vertexWorld : TEXCOORD1;
            };

            float4 _Color;
            float _Gaps;
            float _Speed;
            float _Curvature;

            float4 Fresnel(float3 viewDir, float3 normal)
            {
                return 1 - max(0, dot(viewDir, normal));
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.worldNormal =  UnityObjectToWorldNormal(v.normal);
                o.vertexWorld = mul(unity_ObjectToWorld, v.vertex).xyz;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float4 col = clamp(0, abs(tan((i.vertexWorld.y + _Time.x * _Speed) * _Gaps)), 1);
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.vertexWorld);
                return _Color * col * (Fresnel(viewDir, i.worldNormal));
            }
            ENDCG
        }
    }
    Fallback "Standard"
}
