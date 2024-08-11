Shader "Custom/WaterShaderRefined"
{
    Properties
    {
        _MainColor ("Main Color", Color) = (0.0, 0.5, 0.7, 1.0)
        _Normal1 ("Normal Map 1", 2D) = "bump" {}
        _Normal2 ("Normal Map 2", 2D) = "bump" {}
        _NormalPow ("Normal Power", Float) = 1
        _WaveSpeed ("Wave Speed", Range(0.1, 2.0)) = 0.5
        _ReflectionStrength ("Reflection Strength", Range(0.1, 1.0)) = 0.5
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderQueue"="Transparent" }
        LOD 200
        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha

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
                half4 tangent : TANGENT;
                half2 uv : TEXCOORD0;
            };

            struct v2f
            {
                half4 position : POSITION;
                half2 uv1 : TEXCOORD0;
                half2 uv2 : TEXCOORD1;
                half3 worldPos : TEXCOORD2;
                half3 worldNormal : TEXCOORD3;
                half3 worldTangent : TEXCOORD4;
                half3 worldBinormal : TEXCOORD5;
                UNITY_FOG_COORDS(1)
            };

            sampler2D _Normal1, _Normal2;
            half4 _Normal1_ST, _Normal2_ST;
            half4 _MainColor;
            half _WaveSpeed, _NormalPow;
            half _ReflectionStrength;

            v2f vert(appdata v)
            {
                v2f o;
                o.position = UnityObjectToClipPos(v.vertex);
                o.uv1 = TRANSFORM_TEX(v.uv, _Normal1);
                o.uv2 = TRANSFORM_TEX(v.uv, _Normal2);

                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;

                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                o.worldTangent = UnityObjectToWorldNormal(v.tangent);
                o.worldBinormal = cross(o.worldNormal, o.worldTangent);

                UNITY_TRANSFER_FOG(o, o.position);
                return o;
            }

            half4 PhongShading(half4 colorRefl, half3 normal, half3 lightDir, half3 viewDir)
            {
                half3 h = normalize(lightDir + viewDir);
                
                return colorRefl * pow(max(0, dot(normal, h)), 16);
            }

            half Fresnel(half3 normal, half3 viewDir, half strength)
            {
                return clamp(1 - pow(dot(normal, viewDir), strength), 0, 4);
            }

            half4 frag(v2f i) : SV_Target
            {
                half3 normal1;
                half3 normal2;
                normal1.xy = (tex2D(_Normal1, i.uv1 + _Time.x * _WaveSpeed).wy * 2 - 1) * _NormalPow;
                normal2.xy = (tex2D(_Normal2, i.uv2 - _Time.x * _WaveSpeed).wy * 2 - 1) * _NormalPow;
                normal1.z = sqrt(1 - saturate(dot(normal1.xy, normal1.xy)));
                normal2.z = sqrt(1 - saturate(dot(normal2.xy, normal2.xy)));
                normal1.xyz = normal1.xzy;
                normal2.xyz = normal2.xzy;
                half3 worldNormal = normalize(normal1 * 1.1 + normal2);
                worldNormal = UnityObjectToWorldNormal(worldNormal);
                
                half3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos);

                half3 reflection = reflect(viewDir, worldNormal);
                half4 reflectedColor = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, -reflection, 0);

                half4 albedo = _MainColor * clamp(0,1,dot(_WorldSpaceLightPos0.xyz, worldNormal));
                half4 specular = PhongShading(_LightColor0, worldNormal, _WorldSpaceLightPos0.xyz, viewDir);

                half4 finalColor = albedo + reflectedColor * _ReflectionStrength * Fresnel(worldNormal, viewDir, 1) + specular * _ReflectionStrength;

                half4 col = saturate(finalColor);
                // col = half4(reflection, 1);
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
}
