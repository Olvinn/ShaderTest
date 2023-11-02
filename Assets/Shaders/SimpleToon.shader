Shader "Unlit/SimpleToon"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _Res ("Resolution", Float) = 3
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float4 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
                float4 normal : TEXCOORD2;
            };

            float4 _Color;
            float4 _MainTex_ST;
            float _Res;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.normal = v.normal;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // sample the texture
                fixed4 col = _Color;    
                float4 indirect = unity_IndirectSpecColor;
                float4 direct = dot(i.normal, _WorldSpaceLightPos0);
                direct = clamp(direct, 0, 1);
                float4 ambient = (1 - direct) * indirect;
                col *= direct + ambient;
                col = clamp(col, 0, 1);
                col *= _Res;
                col = floor(col);
                col /= _Res;
                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
}
