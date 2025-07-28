Shader "Custom/WaterShaderRefined"
{
    Properties
    {
        _Color ("Color", Color) = (0.5, 0.8, 0.5, 0.5)
        _Normal ("Normal Map", 2D) = "Normal" {}
        _Detail ("Detail Map", 2D) = "Detail" {}
        _NormalPow ("Normal Power", Float) = .8
        _DetailPow ("Detail Power", Float) = .8
        _Fresnel ("Fresnel", Float) = 5
        _SpecPow ("Specular Power", Float) = 10
    }

    SubShader
    {
        Name "Water"
        Tags { "RenderType" = "Transparent" "RenderQueue" = "Transparent" "LightMode" = "ForwardBase" }
        ZWrite On
        Blend SrcAlpha OneMinusSrcAlpha
            
        Pass
        {
            CGPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile_fwdbase
            
            #include "UnityStandardUtils.cginc"
            #include "UnityLightingCommon.cginc"
            #include "Autolight.cginc"
            #include "Helper.cginc"

            sampler2D _Normal, _Detail;
            half4 _Normal_ST, _Detail_ST, _Color;
            float _NormalPow, _DetailPow, _Fresnel, _SpecPow;

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
                half2 uv0 : TEXCOORD1; 
                half2 uv1 : TEXCOORD2; 
                half3 normal : TEXCOORD3;
                half4 tangent : TEXCOORD4;
                SHADOW_COORDS(5)
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
	            o.worldPos = mul(unity_ObjectToWorld, v.vertex);
	            o.uv0 = TRANSFORM_TEX(v.uv, _Normal);
	            o.uv1 = TRANSFORM_TEX(v.uv, _Detail);
	            o.normal = UnityObjectToWorldNormal(v.normal);
	            o.tangent = half4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
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

            half4 GoochShading(half3 colorRefl, half3 normal, half3 lightDir, half4 warmCol, half4 coldCol, half shadow)
            {
                half g = min(step(1, (dot(normal, lightDir) + 1)), shadow);
                half4 warm = warmCol + half4(colorRefl, 1) * .1;
                half4 cold = coldCol;
                return lerp(cold, warm, g);
            }

            half4 frag(v2f i) : SV_Target
            {
	            float3 normal = UnpackScaleNormal(tex2D(_Normal, (i.worldPos.xz * _Normal_ST) + _Time.x), 1);
	            normal = normal.xzy;
                normal.y = 1 / _NormalPow;
	            float3 detail = UnpackScaleNormal(tex2D(_Detail, (i.worldPos.xz * _Detail_ST) - _Time.x), 1);
	            detail = detail.xzy;
                detail.y = 1 / _DetailPow;
                normal += detail;
	            float3 binormal = cross(i.normal, i.tangent.xyz) * i.tangent.w;
                normal = normalize(
		            normal.x * i.tangent +
		            normal.y * i.normal +
		            normal.z * binormal
	            );
                
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos.xyz);
                float3 reflectWorld = reflect(-viewDir, normal);
                float3 ambientData = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflectWorld, 0);
                half4 ambient = half4(DecodeHDR(half4(ambientData, 1), unity_SpecCube0_HDR), 1);
                fixed shadow = UNITY_SHADOW_ATTENUATION(i, i.worldPos);
                
                float NdotV = saturate(dot(normal, -viewDir));
                float3 F0 = lerp(float3(0.02, 0.02, 0.02), _Color, 0);
                float3 fresnel = FresnelSchlick(NdotV, F0);
                float3 specular = PBRSpecular(normal, viewDir, _WorldSpaceLightPos0.xyz, _Color, 0, .2);
                
                half4 diffuse = GoochShading(_LightColor0.rgb, normal, _WorldSpaceLightPos0.xyz,
                    lerp(_Color, ambient, fresnel.x * fresnel.y * fresnel.z),
                    lerp(_Color, ambient, fresnel.x * fresnel.y * fresnel.z) * .9, shadow) +
                        float4(ShadeSH9(float4(i.normal, 1)), 1.0) * .2; 
                float fresnelDistance = Fresnel(i.normal, viewDir, _Fresnel);

                diffuse.rgb = lerp(diffuse, ambient, fresnel) * max(0.9, shadow);
                diffuse.rgb += specular * _SpecPow;
                diffuse.a = saturate(specular + fresnelDistance);
                diffuse = saturate(diffuse); 

                return diffuse;
            }
            
            ENDCG
        }
    }
    FallBack "Diffuse"
}
