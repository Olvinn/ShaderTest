Shader "Custom/WaterShaderRefined"
{
    Properties
    {
        _MainColor ("Main Color", Color) = (0.0, 0.5, 0.7, 1.0)
        _Normal1 ("Normal Map 1", 2D) = "bump" {}
        _Normal2 ("Normal Map 2", 2D) = "bump" {}
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
                half2 uv : TEXCOORD0;
            };

            struct v2f
            {
                half4 position : POSITION;
                half2 uv1 : TEXCOORD0;
                half2 uv2 : TEXCOORD1;
                half3 worldPos : TEXCOORD2;
                half3 normal : TEXCOORD3;
                UNITY_FOG_COORDS(1)
            };

            sampler2D _Normal1, _Normal2;
            half4 _Normal1_ST, _Normal2_ST;
            half4 _MainColor;
            half _WaveSpeed;
            half _ReflectionStrength;

            v2f vert(appdata v)
            {
                v2f o;
                o.position = UnityObjectToClipPos(v.vertex);
                o.uv1 = TRANSFORM_TEX(v.uv, _Normal1);
                o.uv2 = TRANSFORM_TEX(v.uv, _Normal2);

                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;

                o.normal = v.normal;

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
                return clamp(1 - pow(dot(normal, viewDir), strength), 0, 1);
            }

            half4 frag(v2f i) : SV_Target
            {
                half4 normal1 = tex2D(_Normal1, i.uv1 + _Time.x * _WaveSpeed) * 2 - 1;
                normal1.xyz = UnityObjectToWorldNormal(normal1.zxy);
                half4 normal2 = tex2D(_Normal2, i.uv2 - _Time.x * _WaveSpeed) * 2 - 1;
                normal2.xyz = UnityObjectToWorldNormal(normal2.zxy);
                half3 worldNormal = normalize(normal1 + normal2);
                // worldNormal = UnityObjectToWorldNormal(worldNormal);
                // worldNormal = (worldNormal.yxz);
                
                half3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos);

                half3 reflection = reflect(viewDir, worldNormal);
                half4 reflectedColor = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, -reflection, 0);

                half4 albedo = _MainColor * (dot(_WorldSpaceLightPos0.xyz, worldNormal) + 1) * .5;
                half4 specular = PhongShading(_LightColor0, worldNormal, _WorldSpaceLightPos0.xyz, viewDir);

                half4 finalColor = lerp(albedo, reflectedColor, _ReflectionStrength) * Fresnel(worldNormal, viewDir, 1) + specular;

                half4 col = saturate(finalColor);
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
}
