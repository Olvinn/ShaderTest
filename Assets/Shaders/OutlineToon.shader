Shader "Unlit/OutlineToon"
{
    Properties
    {
        _MainTex ("Texture", 2D ) = "white" {}
        _WarmColor ("Warm Tint", Color) = (1,1,1,1)
        _ColdColor ("Cold Tint", Color) = (0,0,0,1)
        _SpecPow ("Specular Power", float) = 1
        _SpecStr ("Specular Strength" , Range(0,1)) = 1 
        _Outline ("Outline", float) = 1
        _OutlineColor ("Outline Collor", Color) = (0,0,0,1)
    }
    SubShader
    {
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
        
        Pass //actual shading
        {            
            Tags { "LightMode" = "ForwardBase" }
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase
            #pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
            #include "AutoLight.cginc"

            struct appdata
            {
                half4 vertex : POSITION;
                half3 normal : NORMAL;
                half3 color : TEXCOORD0;
                half2 uv : TEXCOORD1;
            };

            struct v2f
            {
                half2 uv : TEXCOORD0;
                SHADOW_COORDS(1)
                UNITY_FOG_COORDS(5)
                half3 worldNormal : TEXCOORD4;
                half3 vertexWorld : TEXCOORD2;
                half3 viewDir : TEXCOORD3;
                float4 pos : SV_POSITION;
            };

            sampler2D _MainTex;
            half4 _WarmColor, _ColdColor;
            half4 _MainTex_ST;
            half _SpecPow,_SpecStr;

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.worldNormal =  UnityObjectToWorldNormal(v.normal);
                o.vertexWorld = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                TRANSFER_SHADOW(o)
                return o;
            }

            half3 GoochShading(half3 colorRefl, half3 normal, half3 lightDir, half3 texCol, half3 warmCol, half3 coldCol, half shadow)
            {
                half g = min(step(1, (dot(normal, lightDir) + 1)), shadow);
                half3 warm = texCol * warmCol + colorRefl * .1;
                half3 cold = texCol * coldCol;
                return lerp(cold, warm, g);
            }

            half3 PhongShading(half3 colorRefl, half power, half3 normal, half3 lightDir, half3 viewDir, half shadow)
            {
                half3 h = normalize(lightDir + viewDir);
                return min(10 * colorRefl * pow(max(0, dot(normal, h)), power), shadow);
            }

            half4 frag (v2f i) : SV_Target
            {
                half4 col = tex2D(_MainTex, i.uv);
                half shadow = floor(SHADOW_ATTENUATION(i)+.7);
                half3 diffuse = GoochShading(_LightColor0.rgb, i.worldNormal, _WorldSpaceLightPos0.xyz,
                    col, _WarmColor, _ColdColor, shadow) + float4(ShadeSH9(float4(i.worldNormal, 1)), 1.0) * .2;
                half3 viewDir = normalize(_WorldSpaceCameraPos - i.vertexWorld); //something wrong!
                half3 specular = PhongShading(_LightColor0.rgb, _SpecPow, i.worldNormal, _WorldSpaceLightPos0.xyz, viewDir, shadow);
                col.rgb = diffuse + specular * _SpecStr;
                // UNITY_APPLY_FOG(i.fogCoord, col);
                return col; 
            }
            ENDCG
        }
        
        Pass //outline
        {
            Tags { "RenderType"="Transparent" }
            
            Cull Front
            Lighting Off
            Blend SrcAlpha OneMinusSrcAlpha
            
            CGPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            half _Outline;
            half4 _OutlineColor;
            
            struct appdata
            {
                half4 vertex : POSITION;
                half3 normal : NORMAL;
            };

            struct v2f
            {
                half4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex + float4(v.normal * _Outline * .1, 1));
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                return _OutlineColor; 
            }
            ENDCG
        }
    }
}
