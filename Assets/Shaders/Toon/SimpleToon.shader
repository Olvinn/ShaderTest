Shader "Unlit/SimpleToon"
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
        Tags { "RenderType"="Opaque" }
        LOD 100
        
        Pass
        {
            Cull Front
            ZWrite On
            
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

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"

            struct appdata
            {
                half4 vertex : POSITION;
                half3 normal : NORMAL;
                half3 color : TEXCOORD0;
                half2 uv : TEXCOORD1;
            };

            struct v2f
            {
                half4 vertex : SV_POSITION;
                half2 uv : TEXCOORD0;
                half3 worldNormal : TEXCOORD1;
                half3 vertexWorld : TEXCOORD2;
                half3 viewDir : TEXCOORD3;
            };

            sampler2D _MainTex;
            half4 _WarmColor, _ColdColor;
            half4 _MainTex_ST;
            half _SpecPow,_SpecStr;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.worldNormal =  UnityObjectToWorldNormal(v.normal);
                o.vertexWorld = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half3 GoochShading(half3 colorRefl, half3 normal, half3 lightDir, half3 texCol, half3 warmCol, half3 coldCol)
            {
                half g = floor((dot(normal, lightDir) + 1));
                half3 warm = texCol * warmCol + colorRefl * .1;
                half3 cold = texCol * coldCol;
                return lerp(cold, warm, g);
            }

            half3 PhongShading(half3 colorRefl, half power, half3 normal, half3 lightDir, half3 viewDir)
            {
                half3 h = normalize(lightDir + viewDir);
                return 10 * colorRefl * pow(max(0, dot(normal, h)), power);
            }

            half4 frag (v2f i) : SV_Target
            {
                half4 col = tex2D(_MainTex, i.uv);
                half3 diffuse = GoochShading(_LightColor0.rgb, i.worldNormal, _WorldSpaceLightPos0.xyz, col, _WarmColor, _ColdColor);
                half3 viewDir = normalize(_WorldSpaceCameraPos - i.vertexWorld); //something wrong!
                half3 specular = PhongShading(_LightColor0.rgb, _SpecPow, i.worldNormal, _WorldSpaceLightPos0.xyz, viewDir);
                col.rgb = diffuse + specular * _SpecStr;
                return col; 
            }
            ENDCG
        }
    }
    
    Fallback "Diffuse"
}
