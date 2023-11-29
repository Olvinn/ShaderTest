Shader "Unlit/VertAndGeometry"
{
    Properties
    {
        _MainTex ("Noise", 2D) = "white" {}
        _SecTex ("Noise2", 2D) = "white" {}
        _TopColor ("Top Color", Color) = (0,1,0,1)
        _BotColor ("Bottom Color", Color) = (0,0,0,1)
        _Offset ("Offset", float) = .1
    }
    SubShader
    {
        Pass
        {
        Tags { "RenderType"="Opaque" "LightMode" = "ShadowCaster" }
        LOD 100
        CGPROGRAM
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment fragShadow
            #pragma target 4.6
            #pragma multi_compile_shadowcaster
            float4 fragShadow(g2f i) : SV_Target
            {
                SHADOW_CASTER_FRAGMENT(i)
            }   
        ENDCG
        }
        
        Pass
        {
            ZWRITE ON
            CGINCLUDE
        
            #define GRASS_LAYERS 16
        
            #include "UnityCG.cginc"
            #include "Autolight.cginc"
        
            struct appdata
            {
                float4 vertex : POSITION;
                float4 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };
        
            struct v2g
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv1 : TEXCOORD0;
                float2 uv2 : TEXCOORD1;
            };
        
            struct g2f
            {
                float2 uv1 : TEXCOORD0;
                float2 uv2 : TEXCOORD3;
                UNITY_FOG_COORDS(4)
                float4 vertex : SV_POSITION;
                float4 height : TEXCOORD2;
                float3 normal : NORMAL;
                unityShadowCoord4 _ShadowCoord : TEXCOORD1;
            };
        
            sampler2D _MainTex, _SecTex;
            float4 _MainTex_ST, _SecTex_ST;
            half _Offset;
            float4 _TopColor, _BotColor;
        
            v2g vert (appdata v)
            {
                v2g o;
                float4 position = v.vertex;
                o.vertex = position;
                o.normal = v.normal;
                o.uv1 = TRANSFORM_TEX(v.uv, _MainTex);
                o.uv2 = TRANSFORM_TEX(v.uv, _SecTex);
                // UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }
        
            [maxvertexcount(3 * GRASS_LAYERS)]
            void geom(triangle v2g input[3], inout TriangleStream<g2f> triStream)
            {
                g2f o;

                for (int l = 0; l < GRASS_LAYERS; l++)
                {
                    for(int i = 0; i < 3; i++)
                    {
                        o.normal = UnityObjectToWorldNormal(input[i].normal);
                        float4 vert = input[i].vertex + float4(o.normal * _Offset * l,0);
                        o.vertex = UnityObjectToClipPos(vert);
                        o.height = l;
                        UNITY_TRANSFER_FOG(o,o.vertex);
                        o.uv1 = input[i].uv1;
                        o.uv2 = input[i].uv2;
                        o._ShadowCoord = ComputeScreenPos(o.vertex);
                        #if UNITY_PASS_SHADOWCASTER
                        o.vertex = UnityApplyLinearShadowBias(o.vertex);
                        #endif
                        triStream.Append(o);
                    }
                    triStream.RestartStrip();
                }
            }
            ENDCG
        }
        
        Pass
        {
            Tags { "RenderType"="Opaque" "LightMode" = "ForwardBase"}
            
            LOD 100
                        
            CGPROGRAM
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase
            #pragma shader_feature IS_LIT
            
            fixed4 frag (g2f i) : SV_Target
            {
                float piece = 1 / (float)GRASS_LAYERS;
                half a = i.height * piece;
                half c = clamp(tex2D(_MainTex, i.uv1 + float2(sin(_Time.x * 10) *.01 * a, 0)) - tex2D(_SecTex, i.uv2 + float2(sin(_Time.x * 10) *.01 * a, 0)) * .5, 0, 1);
                fixed4 col = lerp(_BotColor,_TopColor, c);
                clip(c - a);
                fixed light = saturate (dot (normalize(_WorldSpaceLightPos0), i.normal));
                // float shadow = SHADOW_ATTENUATION(i);
                col.rgb *= light + float4(ShadeSH9(float4(i.normal, 1)), 1.0);  
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
}