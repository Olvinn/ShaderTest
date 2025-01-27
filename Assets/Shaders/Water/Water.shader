Shader "Custom/WaterShaderRefined"
{
    Properties
    {
        _Color ("Color", Color) = (0.5, 0.8, 0.5, 0.5)
        _Normal ("Normal Map", 2D) = "Normal" {}
        _NormalPow ("Normal Power", Float) = .8
        _Fresnel ("Fresnel", Float) = 5
        _SpecPow ("Specular Power", Float) = 10
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "RenderQueue" = "Transparent" "LightMode" = "ForwardBase" }
        ZWrite On
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile_fwdbase
            
            #include "UnityCG.cginc"
            #include "UnityStandardUtils.cginc"
            #include "UnityLightingCommon.cginc"
            #include "Autolight.cginc"

            sampler2D _Normal;
            half4 _Normal_ST, _Color;
            float _NormalPow, _Fresnel, _SpecPow;

            struct appdata
            {
                half4 vertex : POSITION;
                half3 normal : NORMAL;
                half4 tangent : TANGENT;
                half2 uv : TEXCOORD0;
            };

            struct v2f
            {
                half4 pos : SV_POSITION; 
                half4 worldPos : TEXCOORD0;
                half2 uv : TEXCOORD1;   
                half3 normal : TEXCOORD2;
                half4 tangent : TEXCOORD3;
                UNITY_FOG_COORDS(4)
                SHADOW_COORDS(5)
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
	            o.worldPos = mul(unity_ObjectToWorld, v.vertex);
	            o.uv = TRANSFORM_TEX(v.uv, _Normal);
	            o.normal = UnityObjectToWorldNormal(v.normal);
	            o.tangent = half4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
                UNITY_TRANSFER_FOG(o, o.position);
                TRANSFER_SHADOW(o);
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

            half4 frag(v2f i) : SV_Target
            {
	            float3 normal = UnpackScaleNormal(tex2D(_Normal, i.worldPos.xz * _Normal_ST.xy), 1);
	            normal = normal.xzy;
                normal.y = 1 / _NormalPow;
	            float3 binormal = cross(i.normal, i.tangent.xyz) * i.tangent.w;
                normal = normalize(
		            normal.x * i.tangent +
		            normal.y * i.normal +
		            normal.z * binormal
	            );
                
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos.xyz);
                float3 reflectWorld = reflect(-viewDir, normal);
                float3 ambientData = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflectWorld, 0);
                half3 ambient = DecodeHDR(half4(ambientData, 1), unity_SpecCube0_HDR);
                fixed shadow = UNITY_SHADOW_ATTENUATION(i, i.worldPos);
                half4 col = _Color * min(0.9, shadow); 
                float3 specular = PhongShading(_LightColor0.rgb, normal, _WorldSpaceLightPos0.xyz, viewDir) * shadow;
                float fresnel = Fresnel(normal, viewDir, _Fresnel);
                
                col.rgb += specular * _SpecPow;
                col.rgb = lerp(col, ambient, fresnel);
                col.a = max(max(max(specular.r, specular.g), specular.b), fresnel);
                col = saturate(col); 
                
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            
            ENDCG
        }
    }
    FallBack "Diffuse"
}
