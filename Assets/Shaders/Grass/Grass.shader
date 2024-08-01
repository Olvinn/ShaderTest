Shader "Unlit/VertAndGeometry"
{
    Properties
    {
        _MainTex ("Deffuse", 2D) = "white" {}
        _NoiseTex ("Noise", 2D) = "white" {}
        _FluffTex ("Fluffiness", 2D) = "white" {}
        _Offset ("Offset", float) = .1
        _FluffLayers ("Fluff Layers", Range(1, 16)) = 8
    }
    SubShader
    {        
        Pass
        {
            ZWRITE ON
            
            Tags { "RenderType"="Opaque" "LightMode" = "ForwardBase"}
            CGPROGRAM
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase
        
            #define GRASS_LAYERS_MAX 16
        
            #include "UnityCG.cginc"
            #include "Autolight.cginc"
                
            struct v2g
            {
                half4 vertex : POSITION;
                half3 normal : NORMAL;
                half2 uv1 : TEXCOORD0;
                half2 uv2 : TEXCOORD1;
            };
        
            struct g2f
            {
                half2 uv1 : TEXCOORD0;
                half2 uv2 : TEXCOORD3;
                UNITY_FOG_COORDS(4)
                half4 vertex : SV_POSITION;
                half4 height : TEXCOORD2;
                half3 normal : NORMAL;
                unityShadowCoord4 _ShadowCoord : TEXCOORD1;
            };
        
            sampler2D _MainTex, _NoiseTex, _FluffTex;
            half4 _MainTex_ST, _NoiseTex_ST;
            half _Offset;
            half _FluffLayers;
        
            v2g vert (appdata_full v)
            {
                v2g o;
                half4 position = v.vertex;
                o.vertex = position;
                o.normal = v.normal;
                o.uv1 = TRANSFORM_TEX(v.texcoord, _MainTex);
                o.uv2 = TRANSFORM_TEX(v.texcoord1, _NoiseTex);
                // UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }
        
            [maxvertexcount(3 * GRASS_LAYERS_MAX)]
            void geom(triangle v2g input[3], inout TriangleStream<g2f> triStream)
            {
                g2f o;

                half h = 1 / _FluffLayers;
                for (int l = 0; l < (int)_FluffLayers; l++)
                {
                    for(int i = 0; i < 3; i++)
                    {
                        o.normal = UnityObjectToWorldNormal(input[i].normal);
                        half4 vert = input[i].vertex + half4(input[i].normal * _Offset * l * h, 0);
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
            
            half4 frag (g2f i) : SV_Target
            {
                half piece = 1 / min(GRASS_LAYERS_MAX, _FluffLayers);
                half a = i.height * piece;
                half c = clamp(tex2D(_FluffTex, i.uv1) -
                    tex2D(_NoiseTex, i.uv2), 0, 1);
                half4 col = tex2D(_MainTex, i.uv1);
                clip(c - a);
                if (a > 0) col = lerp(col * .75, col, a);
                half light = saturate (dot (normalize(_WorldSpaceLightPos0), i.normal));
                half shadow = 1;// SHADOW_ATTENUATION(i);
                col.rgb *= light * shadow + half4(ShadeSH9(half4(i.normal, 1)), 1.0);
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }

        Pass //shadow casting
        {
            Tags{ "LightMode" = "ShadowCaster" }
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            float4 vert(float4 vertex : POSITION) : SV_POSITION
            {
                return UnityObjectToClipPos(vertex);
            }
            
            float4 frag(float4 vertex : SV_POSITION) : SV_TARGET
            {
                return 0;
            }
                     
            ENDCG
        }
    }
}